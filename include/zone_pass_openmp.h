
#pragma once

#include <cstdint>
#include <vector>

#include "types.h"
#include "zone_pass.h"

namespace mpcd {

struct OpenMPPassMetrics {
    int nZones = 0;
    int nThreadsRequested = 1;
    int nThreadsUsed = 1;
    int nParticlesMovedDense = 0;
    int nParticlesMovedSparse = 0;
    double corrRmsDU = 0.0;
    double corrMaxDU = 0.0;
    double timeLayout = 0.0;
    double timeZoneExtract = 0.0;
    double timeSnapshot = 0.0;
    double timeAlloc = 0.0;
    double timeKernel = 0.0;
    double timePack = 0.0;
    double timeMerge = 0.0;
};

struct OpenMPPassResult {
    State stateOut;
    std::vector<std::int32_t> zoneOwnerMap;
    OpenMPPassMetrics metrics;
};

OpenMPPassResult run_zone_pass_openmp(const State& stateIn,
                                      const Params& params,
                                      const std::string& layoutMode,
                                      std::uint64_t rngSeedBase,
                                      int nThreadsRequested);

OpenMPPassResult run_zone_pass_openmp_base(const State& stateIn,
                                           const Params& params,
                                           std::uint64_t rngSeedBase,
                                           int nThreadsRequested);

OpenMPPassResult run_zone_pass_sync_serial(const State& stateIn,
                                           const Params& params,
                                           const std::string& layoutMode,
                                           std::uint64_t rngSeedBase);

OpenMPPassResult run_zone_pass_sync_serial_base(const State& stateIn,
                                                const Params& params,
                                                std::uint64_t rngSeedBase);

} // namespace mpcd
