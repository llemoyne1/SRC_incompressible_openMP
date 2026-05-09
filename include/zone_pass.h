#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <vector>

#include "types.h"

namespace mpcd {

struct ZoneDescriptor {
    int id = 0;
    std::vector<int> cellIds;
    std::vector<char> maskVec;
};

struct ZoneLayout {
    std::string mode;
    std::vector<ZoneDescriptor> zones;
    std::vector<std::int32_t> ownerMap; // Ny x Nx, linear in MATLAB-like ordering: iy + Ny*ix
};

struct ZoneKernelStats {
    std::array<double, 6> stats{};
    std::array<double, 10> diag{};
    int movedDense = 0;
    int movedSparse = 0;
};

struct ZonePassMetrics {
    double occStdBefore = 0.0;
    double occStdAfter = 0.0;
    double outBandBefore = 0.0;
    double outBandAfter = 0.0;
    int nDenseBefore = 0;
    int nDenseAfter = 0;
    int nSparseBefore = 0;
    int nSparseAfter = 0;
    int nEmptyActiveBefore = 0;
    int nEmptyActiveAfter = 0;
    int nParticlesMovedDense = 0;
    int nParticlesMovedSparse = 0;
    int nZonesExecuted = 0;
    double corrRmsDU = 0.0;
    double corrMaxDU = 0.0;
    double momentumDeltaX = 0.0;
    double momentumDeltaY = 0.0;
    std::string layoutMode;
};

struct ZonePassResult {
    State stateOut;
    CellFields beforeFields;
    CellFields afterFields;
    ZonePassMetrics metrics;
    std::vector<std::int32_t> zoneOwnerMap;
};

ZoneLayout build_zone_layout(const Params& params, const std::string& mode);

ZoneKernelStats run_zone_kernel_inplace(std::vector<double>& x,
                                        std::vector<double>& v,
                                        const Params& params,
                                        const ZoneDescriptor& zone,
                                        std::uint64_t rngSeed,
                                        const std::vector<double>& fluidFractionMask = std::vector<double>());

std::vector<int> build_particle_ids_in_zone(const std::vector<double>& x,
                                            const Params& params,
                                            const ZoneDescriptor& zone);

ZonePassResult run_zone_pass(const State& stateIn,
                             const Params& params,
                             const std::string& layoutMode,
                             std::uint64_t rngSeedBase,
                             const std::vector<double>& fluidFractionMask = std::vector<double>());

void write_i32_grid_bin(const std::string& filepath, int Nx, int Ny, const std::vector<std::int32_t>& data);

} // namespace mpcd
