#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "types.h"

namespace mpcd {

struct LiquidClosureMetrics {
    double betaRepairOpt = 0.0;
    double betaRepairApplied = 0.0;
    double betaRepairNum = 0.0;
    double betaRepairDen = 0.0;
    double betaEOSApplied = 0.0;
    double meanPdriveRaw = 0.0;
    double meanPdrive = 0.0;
    double rmsRepairDU = 0.0;
    double meanAbsRepairDU = 0.0;
    double maxRepairDU = 0.0;
    double rmsEOSDU = 0.0;
    double maxEOSDU = 0.0;
    double momentumDeltaX = 0.0;
    double momentumDeltaY = 0.0;
    int nMaskedInterzoneCells = 0;
};

struct LiquidClosureResult {
    State stateOut;
    State stateRepaired;
    CellFields refFields;
    CellFields redFields;
    CellFields repairedFields;
    CellFields outFields;
    std::vector<double> pdriveRaw;
    std::vector<double> pdrive;
    std::vector<double> duRepairX;
    std::vector<double> duRepairY;
    std::vector<double> duEOSX;
    std::vector<double> duEOSY;
    std::vector<std::int32_t> interzoneMask;
    LiquidClosureMetrics metrics;
};

LiquidClosureResult run_liquid_closure(const State& stateRef,
                                       const State& stateRed,
                                       const Params& params);

void write_f64_grid_bin(const std::string& filepath, int Nx, int Ny, const std::vector<double>& data);
void write_i32_grid_bin_lc(const std::string& filepath, int Nx, int Ny, const std::vector<std::int32_t>& data);

} // namespace mpcd
