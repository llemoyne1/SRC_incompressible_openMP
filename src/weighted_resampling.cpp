#include "weighted_resampling.h"

#include "immersed_solid.h"

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

bool cell_center_inside_domain(int ix, int iy, const CellGrid& grid, const FluidDomainBounds& domain) {
    const double x = (static_cast<double>(ix) + 0.5) * grid.dx;
    const double y = (static_cast<double>(iy) + 0.5) * grid.dy;
    return point_is_inside_fluid_domain(x, y, domain);
}

bool cell_is_active_for_resampling(int ix,
                                   int iy,
                                   const CellGrid& grid,
                                   const SimulationParams& params,
                                   const FluidDomainBounds& domain,
                                   double time) {
    if (!cell_center_inside_domain(ix, iy, grid, domain)) {
        return false;
    }
    if (!immersed_solid_enabled(params)) {
        return true;
    }
    const double solidFraction = immersed_solid_fraction_in_cell(
        ix, iy, grid, GridShift{}, params, domain, time);
    const double fluidFraction = 1.0 - solidFraction;
    return fluidFraction > params.resamplingActiveFluidFractionThreshold;
}

struct PassiveCellPairCandidate {
    std::int32_t donorCell = kInvalidCellIndex;
    std::int32_t receiverCell = kInvalidCellIndex;
    double distance = 0.0;
};

double passive_cell_distance(std::int32_t a,
                             std::int32_t b,
                             const CellGrid& grid,
                             const SimulationParams& params) {
    if (a < 0 || b < 0 || grid.Nx <= 0 || grid.Ny <= 0) {
        return 0.0;
    }
    const int ax = static_cast<int>(a) % grid.Nx;
    const int ay = static_cast<int>(a) / grid.Nx;
    const int bx = static_cast<int>(b) % grid.Nx;
    const int by = static_cast<int>(b) / grid.Nx;

    int dx = std::abs(ax - bx);
    int dy = std::abs(ay - by);
    if (is_x_periodic(params)) {
        dx = std::min(dx, grid.Nx - dx);
    }
    if (is_y_periodic(params)) {
        dy = std::min(dy, grid.Ny - dy);
    }
    return std::sqrt(static_cast<double>(dx * dx + dy * dy));
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
    diagnostics.poolCanSeedReceivers = poolDiagnostics.freeSlots >= diagnostics.nReceiverCells;
    diagnostics.hypotheticalPoolFreeSlotsAfterExtraction =
        poolDiagnostics.freeSlots + diagnostics.nExtractionParticles;
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

        ws.activeCell.assign(static_cast<std::size_t>(numCells), 0u);
        ws.wetCell.assign(static_cast<std::size_t>(numCells), 0u);
        ws.dryCell.assign(static_cast<std::size_t>(numCells), 0u);
        ws.poorCell.assign(static_cast<std::size_t>(numCells), 0u);
        ws.richCell.assign(static_cast<std::size_t>(numCells), 0u);
        ws.targetBandCell.assign(static_cast<std::size_t>(numCells), 0u);
        ws.receiverPoorCells.reserve(static_cast<std::size_t>(numCells));
        ws.donorRichCells.reserve(static_cast<std::size_t>(numCells));
        ws.emptyWetReceiverCells.reserve(static_cast<std::size_t>(numCells));
        ws.transferPlan.reserve(static_cast<std::size_t>(numCells));
        ws.selectedDonorParticles.reserve(static_cast<std::size_t>(numParticles));
        ws.passiveExtractionOperations.reserve(static_cast<std::size_t>(numParticles));
        ws.donorSelectedParticleCount.assign(static_cast<std::size_t>(numCells), 0u);
        ws.donorSelectedMass.assign(static_cast<std::size_t>(numCells), 0.0);
    }
}

WeightedResamplingDiagnostics deposit_weighted_real_fluid(const ParticleState& state,
                                                          const SimulationParams& params,
                                                          const CellGrid& grid,
                                                          const FluidDomainBounds& domain,
                                                          double time,
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
    std::fill(ws.activeCell.begin(), ws.activeCell.end(), 0u);
    std::fill(ws.wetCell.begin(), ws.wetCell.end(), 0u);
    std::fill(ws.dryCell.begin(), ws.dryCell.end(), 0u);
    std::fill(ws.poorCell.begin(), ws.poorCell.end(), 0u);
    std::fill(ws.richCell.begin(), ws.richCell.end(), 0u);
    std::fill(ws.targetBandCell.begin(), ws.targetBandCell.end(), 0u);
    ws.receiverPoorCells.clear();
    ws.donorRichCells.clear();
    ws.emptyWetReceiverCells.clear();
    ws.transferPlan.clear();
    ws.selectedDonorParticles.clear();
    ws.passiveExtractionOperations.clear();
    std::fill(ws.donorSelectedParticleCount.begin(), ws.donorSelectedParticleCount.end(), 0u);
    std::fill(ws.donorSelectedMass.begin(), ws.donorSelectedMass.end(), 0.0);

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
    // Passive active/wet/dry and poor/rich classification.  The default
    // active_domain mask marks every active fluid-domain cell as wet, so a true
    // void pocket inside the fluid is classified as poor instead of being
    // silently treated as a dry/free-surface cell.  The optional occupied mode
    // is provided for future free-surface/injection tests where empty cells must
    // remain dry/latent.
    std::uint64_t nActive = 0u;
    std::uint64_t nWet = 0u;
    std::uint64_t nDry = 0u;
    std::uint64_t nOccupiedDry = 0u;
    double activeMassSum = 0.0;

#pragma omp parallel for reduction(+:nActive,nWet,nDry,nOccupiedDry,activeMassSum) if(nc > 256)
    for (int c = 0; c < nc; ++c) {
        const int ix = c % grid.Nx;
        const int iy = c / grid.Nx;
        const bool active = cell_is_active_for_resampling(ix, iy, grid, params, domain, time);
        const double mc = ws.mass[static_cast<std::size_t>(c)];
        bool wet = false;
        if (active) {
            if (params.resamplingWetMaskMode == "occupied") {
                wet = mc > params.resamplingWetCellMassThreshold;
            } else {
                wet = true;
            }
        }
        const bool dry = !wet;
        ws.activeCell[static_cast<std::size_t>(c)] = active ? 1u : 0u;
        ws.wetCell[static_cast<std::size_t>(c)] = wet ? 1u : 0u;
        ws.dryCell[static_cast<std::size_t>(c)] = dry ? 1u : 0u;
        nActive += active ? 1u : 0u;
        nWet += wet ? 1u : 0u;
        nDry += dry ? 1u : 0u;
        nOccupiedDry += (dry && mc > params.resamplingWetCellMassThreshold) ? 1u : 0u;
        activeMassSum += wet ? mc : 0.0;
    }

    d.targetCellMass = params.resamplingTargetCellMass > 0.0
        ? params.resamplingTargetCellMass
        : (nWet > 0u ? activeMassSum / static_cast<double>(nWet) : d.meanMass);

    d.cellClassificationComputed = true;
    d.nActiveCells = nActive;
    d.nWetCells = nWet;
    d.nDryCells = nDry;
    d.nOccupiedDryCells = nOccupiedDry;
    d.wetMassThreshold = params.resamplingWetCellMassThreshold;
    d.poorMassThreshold = d.targetCellMass * params.resamplingPoorCellMassFraction;
    d.richMassThreshold = d.targetCellMass * params.resamplingRichCellMassFraction;
    d.wetCellFraction = invNc > 0.0 ? static_cast<double>(nWet) * invNc : 0.0;
    d.dryCellFraction = invNc > 0.0 ? static_cast<double>(nDry) * invNc : 0.0;

    if (d.targetCellMass > 0.0) {
        double rel2 = 0.0;
        double relMax = 0.0;
        std::uint64_t nPoor = 0u;
        std::uint64_t nRich = 0u;
        std::uint64_t nTargetBand = 0u;
        std::uint64_t nEmptyWet = 0u;
#pragma omp parallel for reduction(+:rel2,nPoor,nRich,nTargetBand,nEmptyWet) reduction(max:relMax) if(nc > 256)
        for (int c = 0; c < nc; ++c) {
            const std::size_t kk = static_cast<std::size_t>(c);
            if (!ws.wetCell[kk]) {
                continue;
            }
            const double mc = ws.mass[kk];
            const double rel = (mc - d.targetCellMass) / d.targetCellMass;
            rel2 += rel * rel;
            relMax = std::max(relMax, std::abs(rel));

            const bool poor = mc < d.poorMassThreshold;
            const bool rich = mc > d.richMassThreshold;
            const bool emptyWet = ws.count[kk] == 0u;
            ws.poorCell[kk] = poor ? 1u : 0u;
            ws.richCell[kk] = rich ? 1u : 0u;
            ws.targetBandCell[kk] = (!poor && !rich) ? 1u : 0u;
            nPoor += poor ? 1u : 0u;
            nRich += rich ? 1u : 0u;
            nTargetBand += (!poor && !rich) ? 1u : 0u;
            nEmptyWet += emptyWet ? 1u : 0u;
        }
        const double invWet = nWet > 0u ? 1.0 / static_cast<double>(nWet) : 0.0;
        d.mRelRms = std::sqrt(rel2 * invWet);
        d.mRelMaxAbs = relMax;
        d.nPoorCells = nPoor;
        d.nRichCells = nRich;
        d.nTargetBandCells = nTargetBand;
        d.nEmptyWetCells = nEmptyWet;
        d.poorCellFraction = static_cast<double>(nPoor) * invWet;
        d.richCellFraction = static_cast<double>(nRich) * invWet;
        d.emptyWetCellFraction = static_cast<double>(nEmptyWet) * invWet;
    }

    if (d.cellClassificationComputed && d.targetCellMass > 0.0) {
        double receiverDeficit = 0.0;
        double donorExcess = 0.0;
        for (int c = 0; c < nc; ++c) {
            const std::size_t kk = static_cast<std::size_t>(c);
            if (!ws.wetCell[kk]) {
                continue;
            }
            if (ws.poorCell[kk]) {
                ws.receiverPoorCells.push_back(static_cast<std::int32_t>(c));
                const double deficit = d.targetCellMass - ws.mass[kk];
                if (deficit > 0.0) {
                    receiverDeficit += deficit;
                }
                if (ws.count[kk] == 0u) {
                    ws.emptyWetReceiverCells.push_back(static_cast<std::int32_t>(c));
                }
            }
            if (ws.richCell[kk]) {
                ws.donorRichCells.push_back(static_cast<std::int32_t>(c));
                const double excess = ws.mass[kk] - d.targetCellMass;
                if (excess > 0.0) {
                    donorExcess += excess;
                }
            }
        }

        d.candidateListsBuilt = true;
        d.nReceiverCells = static_cast<std::uint64_t>(ws.receiverPoorCells.size());
        d.nDonorCells = static_cast<std::uint64_t>(ws.donorRichCells.size());
        d.nEmptyWetReceiverCells = static_cast<std::uint64_t>(ws.emptyWetReceiverCells.size());
        if (!ws.receiverPoorCells.empty()) {
            d.firstReceiverCell = ws.receiverPoorCells.front();
            d.lastReceiverCell = ws.receiverPoorCells.back();
        }
        if (!ws.donorRichCells.empty()) {
            d.firstDonorCell = ws.donorRichCells.front();
            d.lastDonorCell = ws.donorRichCells.back();
        }
        d.receiverMassDeficitToTarget = receiverDeficit;
        d.donorMassExcessAboveTarget = donorExcess;
        d.donorReceiverMassBalance = donorExcess - receiverDeficit;
        d.potentialTransferMass = std::min(receiverDeficit, donorExcess);
        if (d.nWetCells > 0u) {
            const double invWet = 1.0 / static_cast<double>(d.nWetCells);
            d.receiverFractionOfWetCells = static_cast<double>(d.nReceiverCells) * invWet;
            d.donorFractionOfWetCells = static_cast<double>(d.nDonorCells) * invWet;
        }

        if (!ws.receiverPoorCells.empty() && !ws.donorRichCells.empty()) {
            std::vector<double> receiverRemaining(ws.receiverPoorCells.size(), 0.0);
            std::vector<double> donorRemaining(ws.donorRichCells.size(), 0.0);
            std::vector<PassiveCellPairCandidate> candidates;
            candidates.reserve(ws.receiverPoorCells.size() * ws.donorRichCells.size());

            for (std::size_t ir = 0; ir < ws.receiverPoorCells.size(); ++ir) {
                const std::int32_t rc = ws.receiverPoorCells[ir];
                const double deficit = d.targetCellMass - ws.mass[static_cast<std::size_t>(rc)];
                receiverRemaining[ir] = deficit > 0.0 ? deficit : 0.0;
            }
            for (std::size_t id = 0; id < ws.donorRichCells.size(); ++id) {
                const std::int32_t dc = ws.donorRichCells[id];
                const double excess = ws.mass[static_cast<std::size_t>(dc)] - d.targetCellMass;
                donorRemaining[id] = excess > 0.0 ? excess : 0.0;
            }

            for (const std::int32_t dc : ws.donorRichCells) {
                for (const std::int32_t rc : ws.receiverPoorCells) {
                    candidates.push_back(PassiveCellPairCandidate{
                        dc, rc, passive_cell_distance(dc, rc, grid, params)});
                }
            }
            std::sort(candidates.begin(), candidates.end(),
                      [](const PassiveCellPairCandidate& a, const PassiveCellPairCandidate& b) {
                          if (a.distance != b.distance) return a.distance < b.distance;
                          if (a.donorCell != b.donorCell) return a.donorCell < b.donorCell;
                          return a.receiverCell < b.receiverCell;
                      });

            double plannedMass = 0.0;
            double massWeightedDistance = 0.0;
            double maxDistance = 0.0;
            std::uint64_t adjacentPairs = 0u;
            constexpr double eps = 1.0e-14;
            const double adjacentLimit = std::sqrt(2.0) + 1.0e-12;

            for (const PassiveCellPairCandidate& cand : candidates) {
                auto idIt = std::find(ws.donorRichCells.begin(), ws.donorRichCells.end(), cand.donorCell);
                auto irIt = std::find(ws.receiverPoorCells.begin(), ws.receiverPoorCells.end(), cand.receiverCell);
                if (idIt == ws.donorRichCells.end() || irIt == ws.receiverPoorCells.end()) {
                    continue;
                }
                const std::size_t id = static_cast<std::size_t>(idIt - ws.donorRichCells.begin());
                const std::size_t ir = static_cast<std::size_t>(irIt - ws.receiverPoorCells.begin());
                if (donorRemaining[id] <= eps || receiverRemaining[ir] <= eps) {
                    continue;
                }
                const double transfer = std::min(donorRemaining[id], receiverRemaining[ir]);
                if (transfer <= eps) {
                    continue;
                }
                donorRemaining[id] -= transfer;
                receiverRemaining[ir] -= transfer;
                ws.transferPlan.push_back(ResamplingTransferPlanEntry{
                    cand.donorCell,
                    cand.receiverCell,
                    transfer,
                    cand.distance,
                    donorRemaining[id],
                    receiverRemaining[ir]});
                plannedMass += transfer;
                massWeightedDistance += transfer * cand.distance;
                maxDistance = std::max(maxDistance, cand.distance);
                if (cand.distance <= adjacentLimit) {
                    adjacentPairs += 1u;
                }
            }

            double remainingReceiver = 0.0;
            double remainingDonor = 0.0;
            for (double v : receiverRemaining) remainingReceiver += v;
            for (double v : donorRemaining) remainingDonor += v;

            d.transferPlanBuilt = true;
            d.nTransferPairs = static_cast<std::uint64_t>(ws.transferPlan.size());
            d.nAdjacentTransferPairs = adjacentPairs;
            d.plannedTransferMass = plannedMass;
            d.remainingReceiverDeficitAfterPlan = remainingReceiver;
            d.remainingDonorExcessAfterPlan = remainingDonor;
            d.transferMassCoverageFraction = d.receiverMassDeficitToTarget > 0.0
                ? plannedMass / d.receiverMassDeficitToTarget : 0.0;
            d.transferMeanCellDistance = plannedMass > 0.0 ? massWeightedDistance / plannedMass : 0.0;
            d.transferMaxCellDistance = maxDistance;
            d.transferPlanDonorLimited = remainingReceiver > eps && remainingDonor <= eps;
            d.transferPlanReceiverLimited = remainingDonor > eps && remainingReceiver <= eps;
            if (!ws.transferPlan.empty()) {
                d.firstTransferDonorCell = ws.transferPlan.front().donorCell;
                d.firstTransferReceiverCell = ws.transferPlan.front().receiverCell;
                d.lastTransferDonorCell = ws.transferPlan.back().donorCell;
                d.lastTransferReceiverCell = ws.transferPlan.back().receiverCell;
            }

            // Patch 0117: passive donor particle selection.
            //
            // Follow the passive transfer plan and select true Fluid particle
            // indices from each donor cell.  The state is deliberately left
            // untouched.  Selection is deterministic: for each plan entry, scan
            // particle indices in increasing order and skip particles already
            // selected by an earlier entry.  Because future extraction operates
            // on indivisible particle slots before exact mass/momentum remap,
            // the selected mass can overshoot the continuous planned mass.
            if (!ws.transferPlan.empty()) {
                std::vector<std::uint8_t> selected(static_cast<std::size_t>(state.Np), 0u);
                double selectedMassTotal = 0.0;
                double selectedMaxMass = 0.0;
                std::uint64_t maxPerEntry = 0u;
                constexpr double selectEps = 1.0e-14;

                for (const ResamplingTransferPlanEntry& entry : ws.transferPlan) {
                    if (entry.donorCell < 0 || entry.plannedMass <= selectEps) {
                        continue;
                    }
                    double selectedForEntry = 0.0;
                    std::uint64_t countForEntry = 0u;
                    for (std::size_t i = 0; i < n; ++i) {
                        if (selected[i]) {
                            continue;
                        }
                        if (!is_fluid_particle(state, i)) {
                            continue;
                        }
                        if (ws.cellId[i] != entry.donorCell) {
                            continue;
                        }
                        const double mp = state.mass[i];
                        if (!(mp > 0.0)) {
                            continue;
                        }
                        selected[i] = 1u;
                        selectedForEntry += mp;
                        selectedMassTotal += mp;
                        selectedMaxMass = std::max(selectedMaxMass, mp);
                        countForEntry += 1u;
                        const std::size_t dc = static_cast<std::size_t>(entry.donorCell);
                        if (dc < ws.donorSelectedParticleCount.size()) {
                            ws.donorSelectedParticleCount[dc] += 1u;
                            ws.donorSelectedMass[dc] += mp;
                        }
                        ws.selectedDonorParticles.push_back(ResamplingSelectedDonorParticle{
                            static_cast<std::uint64_t>(i),
                            entry.donorCell,
                            entry.receiverCell,
                            mp,
                            entry.plannedMass,
                            selectedForEntry});
                        if (selectedForEntry + selectEps >= entry.plannedMass) {
                            break;
                        }
                    }
                    maxPerEntry = std::max(maxPerEntry, countForEntry);
                }

                std::uint64_t donorCellsWithSelection = 0u;
                std::uint64_t maxPerCell = 0u;
                for (int c = 0; c < nc; ++c) {
                    const std::uint32_t cc = ws.donorSelectedParticleCount[static_cast<std::size_t>(c)];
                    if (cc > 0u) {
                        donorCellsWithSelection += 1u;
                        maxPerCell = std::max(maxPerCell, static_cast<std::uint64_t>(cc));
                    }
                }

                d.donorParticleSelectionBuilt = d.transferPlanBuilt;
                d.nSelectedDonorParticles = static_cast<std::uint64_t>(ws.selectedDonorParticles.size());
                d.nDonorCellsWithSelectedParticles = donorCellsWithSelection;
                d.maxSelectedParticlesForTransferEntry = maxPerEntry;
                d.maxSelectedParticlesPerDonorCell = maxPerCell;
                d.selectedDonorParticleMass = selectedMassTotal;
                d.selectedDonorMassOvershoot = selectedMassTotal - d.plannedTransferMass;
                d.selectedDonorMassCoverageFraction = d.plannedTransferMass > 0.0
                    ? selectedMassTotal / d.plannedTransferMass : 0.0;
                d.selectedDonorMeanParticleMass = d.nSelectedDonorParticles > 0u
                    ? selectedMassTotal / static_cast<double>(d.nSelectedDonorParticles) : 0.0;
                d.selectedDonorMaxParticleMass = selectedMaxMass;
                d.donorParticleSelectionExactOrOvershoot =
                    selectedMassTotal + selectEps >= d.plannedTransferMass;
                d.donorParticleSelectionUnderfilled =
                    selectedMassTotal + selectEps < d.plannedTransferMass;
                if (!ws.selectedDonorParticles.empty()) {
                    const auto& first = ws.selectedDonorParticles.front();
                    const auto& last = ws.selectedDonorParticles.back();
                    d.firstSelectedDonorParticle = first.particleIndex;
                    d.lastSelectedDonorParticle = last.particleIndex;
                    d.firstSelectedDonorCell = first.donorCell;
                    d.lastSelectedDonorCell = last.donorCell;
                    d.firstSelectedReceiverCell = first.receiverCell;
                    d.lastSelectedReceiverCell = last.receiverCell;
                }

                // Patch 0118: passive extraction operation plan.
                //
                // Convert the 0117 selected donor-particle list into explicit
                // extraction operations that a future mutating patch can apply
                // by changing role Fluid -> Inactive and pushing the extracted
                // slots into the free-list.  This builder is deliberately
                // read-only: it records mass, momentum and kinetic energy but
                // never changes state.role, state.mass, state.x or state.v.
                if (!ws.selectedDonorParticles.empty()) {
                    std::vector<std::uint8_t> seenExtracted(static_cast<std::size_t>(state.Np), 0u);
                    std::vector<std::uint8_t> donorCellSeen(static_cast<std::size_t>(nc), 0u);
                    std::vector<std::uint8_t> receiverCellSeen(static_cast<std::size_t>(nc), 0u);
                    double extractionMass = 0.0;
                    double extractionPx = 0.0;
                    double extractionPy = 0.0;
                    double extractionKinetic = 0.0;
                    double extractionMaxMass = 0.0;
                    bool allSelectedAreFluid = true;
                    bool noDuplicateParticles = true;
                    std::uint64_t donorCells = 0u;
                    std::uint64_t receiverCells = 0u;

                    for (const ResamplingSelectedDonorParticle& selectedParticle : ws.selectedDonorParticles) {
                        const std::uint64_t pi64 = selectedParticle.particleIndex;
                        if (pi64 == kInvalidParticleIndex || pi64 >= state.Np) {
                            allSelectedAreFluid = false;
                            noDuplicateParticles = false;
                            continue;
                        }
                        const std::size_t pi = static_cast<std::size_t>(pi64);
                        if (seenExtracted[pi]) {
                            noDuplicateParticles = false;
                            continue;
                        }
                        seenExtracted[pi] = 1u;

                        const bool isFluid = is_fluid_particle(state, pi);
                        allSelectedAreFluid = allSelectedAreFluid && isFluid;
                        const double mp = state.mass[pi];
                        const double vx = state.vx[pi];
                        const double vy = state.vy[pi];
                        const double px = mp * vx;
                        const double py = mp * vy;
                        const double ke = 0.5 * mp * (vx * vx + vy * vy);

                        if (selectedParticle.donorCell >= 0 && selectedParticle.donorCell < nc) {
                            const std::size_t dc = static_cast<std::size_t>(selectedParticle.donorCell);
                            if (!donorCellSeen[dc]) {
                                donorCellSeen[dc] = 1u;
                                donorCells += 1u;
                            }
                        }
                        if (selectedParticle.receiverCell >= 0 && selectedParticle.receiverCell < nc) {
                            const std::size_t rc = static_cast<std::size_t>(selectedParticle.receiverCell);
                            if (!receiverCellSeen[rc]) {
                                receiverCellSeen[rc] = 1u;
                                receiverCells += 1u;
                            }
                        }

                        extractionMass += mp;
                        extractionPx += px;
                        extractionPy += py;
                        extractionKinetic += ke;
                        extractionMaxMass = std::max(extractionMaxMass, mp);
                        ws.passiveExtractionOperations.push_back(ResamplingPassiveExtractionOperation{
                            pi64,
                            selectedParticle.donorCell,
                            selectedParticle.receiverCell,
                            mp,
                            px,
                            py,
                            ke,
                            particle_role_value(state, pi),
                            static_cast<std::uint8_t>(ParticleRole::Inactive)});
                    }

                    d.extractionPlanBuilt = d.donorParticleSelectionBuilt;
                    d.nExtractionOperations = static_cast<std::uint64_t>(ws.passiveExtractionOperations.size());
                    d.nExtractionParticles = d.nExtractionOperations;
                    d.nExtractionDonorCells = donorCells;
                    d.nExtractionReceiverCells = receiverCells;
                    d.extractionMass = extractionMass;
                    d.extractionMomentumX = extractionPx;
                    d.extractionMomentumY = extractionPy;
                    d.extractionKineticEnergy = extractionKinetic;
                    d.extractionMeanParticleMass = d.nExtractionParticles > 0u
                        ? extractionMass / static_cast<double>(d.nExtractionParticles) : 0.0;
                    d.extractionMaxParticleMass = extractionMaxMass;
                    d.extractionMassOvershoot = extractionMass - d.plannedTransferMass;
                    d.extractionMassCoverageFraction = d.plannedTransferMass > 0.0
                        ? extractionMass / d.plannedTransferMass : 0.0;
                    d.hypotheticalPoolFreeSlotsAfterExtraction = d.poolFreeSlots + d.nExtractionParticles;
                    d.extractionAllSelectedAreFluid = allSelectedAreFluid;
                    d.extractionNoDuplicateParticles = noDuplicateParticles;
                    if (!ws.passiveExtractionOperations.empty()) {
                        const auto& first = ws.passiveExtractionOperations.front();
                        const auto& last = ws.passiveExtractionOperations.back();
                        d.firstExtractionParticle = first.particleIndex;
                        d.lastExtractionParticle = last.particleIndex;
                        d.firstExtractionDonorCell = first.donorCell;
                        d.lastExtractionDonorCell = last.donorCell;
                        d.firstExtractionReceiverCell = first.receiverCell;
                        d.lastExtractionReceiverCell = last.receiverCell;
                    }
                } else {
                    d.extractionPlanBuilt = d.donorParticleSelectionBuilt;
                    d.hypotheticalPoolFreeSlotsAfterExtraction = d.poolFreeSlots;
                    d.extractionAllSelectedAreFluid = d.donorParticleSelectionBuilt;
                    d.extractionNoDuplicateParticles = d.donorParticleSelectionBuilt;
                }
            }
        } else {
            d.transferPlanBuilt = d.candidateListsBuilt;
            d.remainingReceiverDeficitAfterPlan = d.receiverMassDeficitToTarget;
            d.remainingDonorExcessAfterPlan = d.donorMassExcessAboveTarget;
        }
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
