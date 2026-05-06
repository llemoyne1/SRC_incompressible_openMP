#include "zone_pass_openmp.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <stdexcept>
#include <vector>

#ifdef _OPENMP
#include <omp.h>
#endif

namespace mpcd {
namespace {
using Clock = std::chrono::steady_clock;

struct LocalTimes {
    double extract = 0.0;
    double snapshot = 0.0;
    double alloc = 0.0;
    double kernel = 0.0;
    double pack = 0.0;
};

struct ZoneBuffer {
    std::vector<int> particleIds;
    std::vector<double> xPacked;
    std::vector<double> vPacked;
    ZoneKernelStats stats;
    LocalTimes times;
};

OpenMPPassResult run_zone_pass_snapshot_impl(const State& stateIn,
                                             const Params& params,
                                             const std::string& layoutMode,
                                             std::uint64_t rngSeedBase,
                                             int nThreadsRequested,
                                             bool useOpenMP) {
    if (!params.useIncompressibleRedistribution || !params.useZoneRedistribution) {
        throw std::runtime_error("run_zone_pass_snapshot_impl requires useIncompressibleRedistribution=true and useZoneRedistribution=true");
    }
    if (params.redistributionEnableSurfaceTopology || params.redistributionWallWettingEnabled || params.useInterfaceVelocityReorientation) {
        throw std::runtime_error("run_zone_pass_snapshot_impl is restricted to no surface / no wetting / no reorientation");
    }

    OpenMPPassResult out{};
    out.stateOut = stateIn;

    auto t0 = Clock::now();
    const ZoneLayout layout = build_zone_layout(params, layoutMode);
    out.metrics.timeLayout = std::chrono::duration<double>(Clock::now() - t0).count();
    out.zoneOwnerMap = layout.ownerMap;
    out.metrics.nZones = static_cast<int>(layout.zones.size());
    out.metrics.nThreadsRequested = std::max(1, nThreadsRequested);

    std::vector<ZoneBuffer> zoneBuf(static_cast<std::size_t>(layout.zones.size()));

#ifdef _OPENMP
    if (useOpenMP) {
        omp_set_dynamic(0);
        omp_set_num_threads(out.metrics.nThreadsRequested);
#pragma omp parallel for schedule(static)
        for (int iz = 0; iz < static_cast<int>(layout.zones.size()); ++iz) {
            ZoneBuffer zb{};
            auto t_extract0 = Clock::now();
            zb.particleIds = build_particle_ids_in_zone(stateIn.x, params, layout.zones[static_cast<std::size_t>(iz)]);
            zb.times.extract += std::chrono::duration<double>(Clock::now() - t_extract0).count();

            auto t_snap0 = Clock::now();
            std::vector<double> xLocal = stateIn.x;
            std::vector<double> vLocal = stateIn.v;
            zb.times.snapshot += std::chrono::duration<double>(Clock::now() - t_snap0).count();

            auto t_kernel0 = Clock::now();
            zb.stats = run_zone_kernel_inplace(xLocal, vLocal, params,
                                               layout.zones[static_cast<std::size_t>(iz)],
                                               rngSeedBase + 104729ULL * static_cast<std::uint64_t>(iz + 1));
            zb.times.kernel += std::chrono::duration<double>(Clock::now() - t_kernel0).count();

            auto t_alloc0 = Clock::now();
            zb.xPacked.resize(2 * zb.particleIds.size());
            zb.vPacked.resize(2 * zb.particleIds.size());
            zb.times.alloc += std::chrono::duration<double>(Clock::now() - t_alloc0).count();

            auto t_pack0 = Clock::now();
            for (std::size_t k = 0; k < zb.particleIds.size(); ++k) {
                const int pid = zb.particleIds[k];
                zb.xPacked[2 * k] = xLocal[2 * pid];
                zb.xPacked[2 * k + 1] = xLocal[2 * pid + 1];
                zb.vPacked[2 * k] = vLocal[2 * pid];
                zb.vPacked[2 * k + 1] = vLocal[2 * pid + 1];
            }
            zb.times.pack += std::chrono::duration<double>(Clock::now() - t_pack0).count();
            zoneBuf[static_cast<std::size_t>(iz)] = std::move(zb);
        }
    } else
#endif
    {
        for (int iz = 0; iz < static_cast<int>(layout.zones.size()); ++iz) {
            ZoneBuffer zb{};
            auto t_extract0 = Clock::now();
            zb.particleIds = build_particle_ids_in_zone(stateIn.x, params, layout.zones[static_cast<std::size_t>(iz)]);
            zb.times.extract += std::chrono::duration<double>(Clock::now() - t_extract0).count();

            auto t_snap0 = Clock::now();
            std::vector<double> xLocal = stateIn.x;
            std::vector<double> vLocal = stateIn.v;
            zb.times.snapshot += std::chrono::duration<double>(Clock::now() - t_snap0).count();

            auto t_kernel0 = Clock::now();
            zb.stats = run_zone_kernel_inplace(xLocal, vLocal, params,
                                               layout.zones[static_cast<std::size_t>(iz)],
                                               rngSeedBase + 104729ULL * static_cast<std::uint64_t>(iz + 1));
            zb.times.kernel += std::chrono::duration<double>(Clock::now() - t_kernel0).count();

            auto t_alloc0 = Clock::now();
            zb.xPacked.resize(2 * zb.particleIds.size());
            zb.vPacked.resize(2 * zb.particleIds.size());
            zb.times.alloc += std::chrono::duration<double>(Clock::now() - t_alloc0).count();

            auto t_pack0 = Clock::now();
            for (std::size_t k = 0; k < zb.particleIds.size(); ++k) {
                const int pid = zb.particleIds[k];
                zb.xPacked[2 * k] = xLocal[2 * pid];
                zb.xPacked[2 * k + 1] = xLocal[2 * pid + 1];
                zb.vPacked[2 * k] = vLocal[2 * pid];
                zb.vPacked[2 * k + 1] = vLocal[2 * pid + 1];
            }
            zb.times.pack += std::chrono::duration<double>(Clock::now() - t_pack0).count();
            zoneBuf[static_cast<std::size_t>(iz)] = std::move(zb);
        }
    }

#ifdef _OPENMP
    out.metrics.nThreadsUsed = useOpenMP ? omp_get_max_threads() : 1;
#else
    out.metrics.nThreadsUsed = 1;
#endif

    double corrAcc2 = 0.0;
    int corrCount = 0;
    double corrMax = 0.0;

    auto t_merge0 = Clock::now();
    for (const auto& zb : zoneBuf) {
        for (std::size_t k = 0; k < zb.particleIds.size(); ++k) {
            const int pid = zb.particleIds[k];
            out.stateOut.x[2 * pid] = zb.xPacked[2 * k];
            out.stateOut.x[2 * pid + 1] = zb.xPacked[2 * k + 1];
            out.stateOut.v[2 * pid] = zb.vPacked[2 * k];
            out.stateOut.v[2 * pid + 1] = zb.vPacked[2 * k + 1];
        }
        out.metrics.nParticlesMovedDense += zb.stats.movedDense;
        out.metrics.nParticlesMovedSparse += zb.stats.movedSparse;
        out.metrics.timeZoneExtract += zb.times.extract;
        out.metrics.timeSnapshot += zb.times.snapshot;
        out.metrics.timeAlloc += zb.times.alloc;
        out.metrics.timeKernel += zb.times.kernel;
        out.metrics.timePack += zb.times.pack;
        if (zb.stats.stats[4] > 0.0) {
            corrAcc2 += zb.stats.stats[4] * zb.stats.stats[4];
            ++corrCount;
        }
        corrMax = std::max(corrMax, zb.stats.stats[5]);
    }
    out.metrics.timeMerge = std::chrono::duration<double>(Clock::now() - t_merge0).count();

    out.metrics.corrRmsDU = (corrCount > 0) ? std::sqrt(corrAcc2 / static_cast<double>(corrCount)) : 0.0;
    out.metrics.corrMaxDU = corrMax;
    return out;
}

} // namespace

OpenMPPassResult run_zone_pass_openmp(const State& stateIn,
                                      const Params& params,
                                      const std::string& layoutMode,
                                      std::uint64_t rngSeedBase,
                                      int nThreadsRequested) {
    return run_zone_pass_snapshot_impl(stateIn, params, layoutMode, rngSeedBase, nThreadsRequested, true);
}

OpenMPPassResult run_zone_pass_openmp_base(const State& stateIn,
                                           const Params& params,
                                           std::uint64_t rngSeedBase,
                                           int nThreadsRequested) {
    return run_zone_pass_openmp(stateIn, params, "base", rngSeedBase, nThreadsRequested);
}

OpenMPPassResult run_zone_pass_sync_serial(const State& stateIn,
                                           const Params& params,
                                           const std::string& layoutMode,
                                           std::uint64_t rngSeedBase) {
    return run_zone_pass_snapshot_impl(stateIn, params, layoutMode, rngSeedBase, 1, false);
}

OpenMPPassResult run_zone_pass_sync_serial_base(const State& stateIn,
                                                const Params& params,
                                                std::uint64_t rngSeedBase) {
    return run_zone_pass_sync_serial(stateIn, params, "base", rngSeedBase);
}

} // namespace mpcd
