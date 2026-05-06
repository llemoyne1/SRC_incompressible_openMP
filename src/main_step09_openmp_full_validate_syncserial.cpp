#include <algorithm>
#include <cmath>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>

#include "boundary_conditions.h"
#include "dump_io.h"
#include "liquid_closure.h"
#include "params_io.h"
#include "srd_collision.h"
#include "state_io.h"
#include "types.h"
#include "zone_pass_openmp.h"

static double mean_abs_xy_diff(const std::vector<double>& a, const std::vector<double>& b, int n, int comp) {
    double s = 0.0;
    for (int i = 0; i < n; ++i) s += std::abs(a[2 * i + comp] - b[2 * i + comp]);
    return s / static_cast<double>(std::max(n, 1));
}

namespace {
mpcd::State build_shared_ref(const mpcd::State& state0,
                             const mpcd::Params& params,
                             mpcd::WallInfo& wallInfo,
                             double& pBotInst,
                             double& pTopInst,
                             double& pMeanInst) {
    mpcd::State stateRef = state0;
    for (int i = 0; i < params.n; ++i) {
        stateRef.v[2 * i] += params.bodyForceX * params.dt;
        stateRef.v[2 * i + 1] += params.g * params.dt;
        stateRef.x[2 * i] += params.dt * stateRef.v[2 * i];
        stateRef.x[2 * i + 1] += params.dt * stateRef.v[2 * i + 1];
    }
    mpcd::apply_bc_general(stateRef.x, stateRef.v, params, wallInfo, 104729ULL);
    pBotInst = wallInfo.dPyBot / std::max(params.Lx * params.dt, 1e-30);
    pTopInst = wallInfo.dPyTop / std::max(params.Lx * params.dt, 1e-30);
    pMeanInst = 0.5 * (pBotInst + pTopInst);
    const auto cid = mpcd::srd_cell_id_with_random_shift(stateRef.x, params, 130363ULL);
    mpcd::srd_collision_step(stateRef.v, cid, params, 433494437ULL);
    return stateRef;
}
}

int main(int argc, char** argv) {
    if (argc != 10) {
        std::cerr << "Usage: " << argv[0] << " params.kv state_x.bin state_v.bin state_type.bin state_r0.bin out_prefix has_type has_r0 nthreads\n";
        return 2;
    }
    const std::string params_path = argv[1], x_path = argv[2], v_path = argv[3], type_path = argv[4], r0_path = argv[5], out_prefix = argv[6];
    const bool has_type = std::string(argv[7]) == "1";
    const bool has_r0 = std::string(argv[8]) == "1";
    const int nthreads = std::max(1, std::stoi(argv[9]));
    try {
        const mpcd::Params params = mpcd::read_params_kv(params_path);
        const mpcd::State state0 = mpcd::read_state(x_path, v_path, type_path, r0_path, has_type, has_r0, params.n);
        mpcd::WallInfo refWall;
        double refPBot = 0.0, refPTop = 0.0, refPMean = 0.0;
        const mpcd::State sharedRef = build_shared_ref(state0, params, refWall, refPBot, refPTop, refPMean);

        const auto serialBase = mpcd::run_zone_pass_sync_serial(sharedRef, params, "base", 88172645463325252ULL);
        const auto serialShifted = mpcd::run_zone_pass_sync_serial(serialBase.stateOut, params, "shifted", 88172645463325252ULL + 4099ULL);
        const auto serialClosure = mpcd::run_liquid_closure(sharedRef, serialShifted.stateOut, params);
        const auto ompBase = mpcd::run_zone_pass_openmp(sharedRef, params, "base", 88172645463325252ULL, nthreads);
        const auto ompShifted = mpcd::run_zone_pass_openmp(ompBase.stateOut, params, "shifted", 88172645463325252ULL + 4099ULL, nthreads);
        const auto ompClosure = mpcd::run_liquid_closure(sharedRef, ompShifted.stateOut, params);

        mpcd::write_xy_interleaved(out_prefix + "_ref_x.bin", sharedRef.x, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_ref_v.bin", sharedRef.v, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_serial_after_base_x.bin", serialBase.stateOut.x, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_serial_after_base_v.bin", serialBase.stateOut.v, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_omp_after_base_x.bin", ompBase.stateOut.x, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_omp_after_base_v.bin", ompBase.stateOut.v, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_serial_x.bin", serialClosure.stateOut.x, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_serial_v.bin", serialClosure.stateOut.v, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_omp_x.bin", ompClosure.stateOut.x, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_omp_v.bin", ompClosure.stateOut.v, params.n);
        mpcd::write_i32_grid_bin(out_prefix + "_zone_owner_base.bin", params.Nx, params.Ny, ompBase.zoneOwnerMap);
        mpcd::write_i32_grid_bin(out_prefix + "_zone_owner_shifted.bin", params.Nx, params.Ny, ompShifted.zoneOwnerMap);

        std::ofstream fout(out_prefix + "_runout.kv");
        fout << "nThreadsRequested=" << ompBase.metrics.nThreadsRequested << '\n';
        fout << "nThreadsUsed=" << std::min(ompBase.metrics.nThreadsUsed, ompShifted.metrics.nThreadsUsed) << '\n';
        fout << "nZonesBase=" << ompBase.metrics.nZones << '\n';
        fout << "nZonesShifted=" << ompShifted.metrics.nZones << '\n';
        fout << "meanAbsDxRef=0\nmeanAbsDyRef=0\nmeanAbsDvxRef=0\nmeanAbsDvyRef=0\n";
        fout << "serial_base_nParticlesMovedDense=" << serialBase.metrics.nParticlesMovedDense << '\n';
        fout << "serial_base_nParticlesMovedSparse=" << serialBase.metrics.nParticlesMovedSparse << '\n';
        fout << "omp_base_nParticlesMovedDense=" << ompBase.metrics.nParticlesMovedDense << '\n';
        fout << "omp_base_nParticlesMovedSparse=" << ompBase.metrics.nParticlesMovedSparse << '\n';
        fout << "serial_shifted_nParticlesMovedDense=" << serialShifted.metrics.nParticlesMovedDense << '\n';
        fout << "serial_shifted_nParticlesMovedSparse=" << serialShifted.metrics.nParticlesMovedSparse << '\n';
        fout << "omp_shifted_nParticlesMovedDense=" << ompShifted.metrics.nParticlesMovedDense << '\n';
        fout << "omp_shifted_nParticlesMovedSparse=" << ompShifted.metrics.nParticlesMovedSparse << '\n';
        fout << "serial_base_corrRmsDU=" << serialBase.metrics.corrRmsDU << '\n';
        fout << "omp_base_corrRmsDU=" << ompBase.metrics.corrRmsDU << '\n';
        fout << "serial_base_corrMaxDU=" << serialBase.metrics.corrMaxDU << '\n';
        fout << "omp_base_corrMaxDU=" << ompBase.metrics.corrMaxDU << '\n';
        fout << "serial_shifted_corrRmsDU=" << serialShifted.metrics.corrRmsDU << '\n';
        fout << "omp_shifted_corrRmsDU=" << ompShifted.metrics.corrRmsDU << '\n';
        fout << "serial_shifted_corrMaxDU=" << serialShifted.metrics.corrMaxDU << '\n';
        fout << "omp_shifted_corrMaxDU=" << ompShifted.metrics.corrMaxDU << '\n';
        fout << "meanAbsDxAfterBase=" << mean_abs_xy_diff(serialBase.stateOut.x, ompBase.stateOut.x, params.n, 0) << '\n';
        fout << "meanAbsDyAfterBase=" << mean_abs_xy_diff(serialBase.stateOut.x, ompBase.stateOut.x, params.n, 1) << '\n';
        fout << "meanAbsDvxAfterBase=" << mean_abs_xy_diff(serialBase.stateOut.v, ompBase.stateOut.v, params.n, 0) << '\n';
        fout << "meanAbsDvyAfterBase=" << mean_abs_xy_diff(serialBase.stateOut.v, ompBase.stateOut.v, params.n, 1) << '\n';
        fout << "meanAbsDxFinal=" << mean_abs_xy_diff(serialClosure.stateOut.x, ompClosure.stateOut.x, params.n, 0) << '\n';
        fout << "meanAbsDyFinal=" << mean_abs_xy_diff(serialClosure.stateOut.x, ompClosure.stateOut.x, params.n, 1) << '\n';
        fout << "meanAbsDvxFinal=" << mean_abs_xy_diff(serialClosure.stateOut.v, ompClosure.stateOut.v, params.n, 0) << '\n';
        fout << "meanAbsDvyFinal=" << mean_abs_xy_diff(serialClosure.stateOut.v, ompClosure.stateOut.v, params.n, 1) << '\n';
        fout << "serial_pBotInst=" << refPBot << '\n';
        fout << "omp_pBotInst=" << refPBot << '\n';
        fout << "serial_pTopInst=" << refPTop << '\n';
        fout << "omp_pTopInst=" << refPTop << '\n';
        fout << "serial_pMeanInst=" << refPMean << '\n';
        fout << "omp_pMeanInst=" << refPMean << '\n';
        fout << "serial_betaRepairApplied=" << serialClosure.metrics.betaRepairApplied << '\n';
        fout << "omp_betaRepairApplied=" << ompClosure.metrics.betaRepairApplied << '\n';
        return 0;
    } catch (const std::exception& e) { std::cerr << "Fatal error: " << e.what() << '\n'; return 1; }
}
