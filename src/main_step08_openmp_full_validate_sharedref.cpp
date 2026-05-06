#include <algorithm>
#include <cmath>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>

#include "boundary_conditions.h"
#include "common_grid.h"
#include "dump_io.h"
#include "liquid_closure.h"
#include "params_io.h"
#include "srd_collision.h"
#include "state_io.h"
#include "types.h"
#include "zone_pass.h"
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

} // namespace

int main(int argc, char** argv) {
    if (argc != 10) {
        std::cerr << "Usage: " << argv[0]
                  << " params.kv state_x.bin state_v.bin state_type.bin state_r0.bin out_prefix has_type has_r0 nthreads\n";
        return 2;
    }
    const std::string params_path = argv[1];
    const std::string x_path = argv[2];
    const std::string v_path = argv[3];
    const std::string type_path = argv[4];
    const std::string r0_path = argv[5];
    const std::string out_prefix = argv[6];
    const bool has_type = std::string(argv[7]) == "1";
    const bool has_r0 = std::string(argv[8]) == "1";
    const int nthreads = std::max(1, std::stoi(argv[9]));

    try {
        const mpcd::Params params = mpcd::read_params_kv(params_path);
        const mpcd::State state0 = mpcd::read_state(x_path, v_path, type_path, r0_path, has_type, has_r0, params.n);

        mpcd::WallInfo refWall;
        double refPBot = 0.0, refPTop = 0.0, refPMean = 0.0;
        const mpcd::State sharedRef = build_shared_ref(state0, params, refWall, refPBot, refPTop, refPMean);

        const mpcd::State seqRef = sharedRef;
        const mpcd::State ompRef = sharedRef;

        const mpcd::ZonePassResult seqBase = mpcd::run_zone_pass(seqRef, params, "base", 88172645463325252ULL);
        const mpcd::ZonePassResult seqShifted = mpcd::run_zone_pass(seqBase.stateOut, params, "shifted", 88172645463325252ULL + 4099ULL);
        const mpcd::LiquidClosureResult seqClosure = mpcd::run_liquid_closure(seqRef, seqShifted.stateOut, params);
        const mpcd::State seqOut = seqClosure.stateOut;

        const mpcd::OpenMPPassResult ompBase = mpcd::run_zone_pass_openmp(ompRef, params, "base", 88172645463325252ULL, nthreads);
        const mpcd::OpenMPPassResult ompShifted = mpcd::run_zone_pass_openmp(ompBase.stateOut, params, "shifted", 88172645463325252ULL + 4099ULL, nthreads);
        const mpcd::LiquidClosureResult ompClosure = mpcd::run_liquid_closure(ompRef, ompShifted.stateOut, params);
        const mpcd::State ompOut = ompClosure.stateOut;

        mpcd::write_xy_interleaved(out_prefix + "_ref_x.bin", sharedRef.x, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_ref_v.bin", sharedRef.v, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_seq_x.bin", seqOut.x, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_seq_v.bin", seqOut.v, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_omp_x.bin", ompOut.x, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_omp_v.bin", ompOut.v, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_seq_after_base_x.bin", seqBase.stateOut.x, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_seq_after_base_v.bin", seqBase.stateOut.v, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_omp_after_base_x.bin", ompBase.stateOut.x, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_omp_after_base_v.bin", ompBase.stateOut.v, params.n);
        if (has_type) {
            mpcd::write_u8(out_prefix + "_ref_type.bin", sharedRef.type, params.n);
            mpcd::write_u8(out_prefix + "_seq_type.bin", seqOut.type, params.n);
            mpcd::write_u8(out_prefix + "_omp_type.bin", ompOut.type, params.n);
        }
        if (has_r0) {
            mpcd::write_xy_interleaved(out_prefix + "_ref_r0.bin", sharedRef.r0, params.n);
            mpcd::write_xy_interleaved(out_prefix + "_seq_r0.bin", seqOut.r0, params.n);
            mpcd::write_xy_interleaved(out_prefix + "_omp_r0.bin", ompOut.r0, params.n);
        }
        mpcd::write_i32_grid_bin(out_prefix + "_zone_owner_base.bin", params.Nx, params.Ny, ompBase.zoneOwnerMap);
        mpcd::write_i32_grid_bin(out_prefix + "_zone_owner_shifted.bin", params.Nx, params.Ny, ompShifted.zoneOwnerMap);

        std::ofstream fout(out_prefix + "_runout.kv");
        if (!fout) throw std::runtime_error("Cannot open runout file for writing");
        fout << "nThreadsRequested=" << ompBase.metrics.nThreadsRequested << '\n';
        fout << "nThreadsUsed=" << std::min(ompBase.metrics.nThreadsUsed, ompShifted.metrics.nThreadsUsed) << '\n';
        fout << "nZonesBase=" << ompBase.metrics.nZones << '\n';
        fout << "nZonesShifted=" << ompShifted.metrics.nZones << '\n';
        fout << "meanAbsDxRef=" << mean_abs_xy_diff(seqRef.x, ompRef.x, params.n, 0) << '\n';
        fout << "meanAbsDyRef=" << mean_abs_xy_diff(seqRef.x, ompRef.x, params.n, 1) << '\n';
        fout << "meanAbsDvxRef=" << mean_abs_xy_diff(seqRef.v, ompRef.v, params.n, 0) << '\n';
        fout << "meanAbsDvyRef=" << mean_abs_xy_diff(seqRef.v, ompRef.v, params.n, 1) << '\n';
        fout << "seq_base_nParticlesMovedDense=" << seqBase.metrics.nParticlesMovedDense << '\n';
        fout << "seq_base_nParticlesMovedSparse=" << seqBase.metrics.nParticlesMovedSparse << '\n';
        fout << "omp_base_nParticlesMovedDense=" << ompBase.metrics.nParticlesMovedDense << '\n';
        fout << "omp_base_nParticlesMovedSparse=" << ompBase.metrics.nParticlesMovedSparse << '\n';
        fout << "seq_shifted_nParticlesMovedDense=" << seqShifted.metrics.nParticlesMovedDense << '\n';
        fout << "seq_shifted_nParticlesMovedSparse=" << seqShifted.metrics.nParticlesMovedSparse << '\n';
        fout << "omp_shifted_nParticlesMovedDense=" << ompShifted.metrics.nParticlesMovedDense << '\n';
        fout << "omp_shifted_nParticlesMovedSparse=" << ompShifted.metrics.nParticlesMovedSparse << '\n';
        fout << "seq_base_corrRmsDU=" << seqBase.metrics.corrRmsDU << '\n';
        fout << "omp_base_corrRmsDU=" << ompBase.metrics.corrRmsDU << '\n';
        fout << "seq_base_corrMaxDU=" << seqBase.metrics.corrMaxDU << '\n';
        fout << "omp_base_corrMaxDU=" << ompBase.metrics.corrMaxDU << '\n';
        fout << "seq_shifted_corrRmsDU=" << seqShifted.metrics.corrRmsDU << '\n';
        fout << "omp_shifted_corrRmsDU=" << ompShifted.metrics.corrRmsDU << '\n';
        fout << "seq_shifted_corrMaxDU=" << seqShifted.metrics.corrMaxDU << '\n';
        fout << "omp_shifted_corrMaxDU=" << ompShifted.metrics.corrMaxDU << '\n';
        fout << "meanAbsDxAfterBase=" << mean_abs_xy_diff(seqBase.stateOut.x, ompBase.stateOut.x, params.n, 0) << '\n';
        fout << "meanAbsDyAfterBase=" << mean_abs_xy_diff(seqBase.stateOut.x, ompBase.stateOut.x, params.n, 1) << '\n';
        fout << "meanAbsDvxAfterBase=" << mean_abs_xy_diff(seqBase.stateOut.v, ompBase.stateOut.v, params.n, 0) << '\n';
        fout << "meanAbsDvyAfterBase=" << mean_abs_xy_diff(seqBase.stateOut.v, ompBase.stateOut.v, params.n, 1) << '\n';
        fout << "meanAbsDxFinal=" << mean_abs_xy_diff(seqOut.x, ompOut.x, params.n, 0) << '\n';
        fout << "meanAbsDyFinal=" << mean_abs_xy_diff(seqOut.x, ompOut.x, params.n, 1) << '\n';
        fout << "meanAbsDvxFinal=" << mean_abs_xy_diff(seqOut.v, ompOut.v, params.n, 0) << '\n';
        fout << "meanAbsDvyFinal=" << mean_abs_xy_diff(seqOut.v, ompOut.v, params.n, 1) << '\n';
        fout << "seq_pBotInst=" << refPBot << '\n';
        fout << "omp_pBotInst=" << refPBot << '\n';
        fout << "seq_pTopInst=" << refPTop << '\n';
        fout << "omp_pTopInst=" << refPTop << '\n';
        fout << "seq_pMeanInst=" << refPMean << '\n';
        fout << "omp_pMeanInst=" << refPMean << '\n';
        fout << "seq_betaRepairApplied=" << seqClosure.metrics.betaRepairApplied << '\n';
        fout << "omp_betaRepairApplied=" << ompClosure.metrics.betaRepairApplied << '\n';
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "Fatal error: " << e.what() << '\n';
        return 1;
    }
}
