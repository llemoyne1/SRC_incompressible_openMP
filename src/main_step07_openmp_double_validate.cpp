#include <algorithm>
#include <cmath>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>

#include "dump_io.h"
#include "params_io.h"
#include "state_io.h"
#include "zone_pass.h"
#include "zone_pass_openmp.h"

static double mean_abs_xy_diff(const std::vector<double>& a, const std::vector<double>& b, int n, int comp) {
    double s = 0.0;
    for (int i = 0; i < n; ++i) s += std::abs(a[2 * i + comp] - b[2 * i + comp]);
    return s / static_cast<double>(std::max(n, 1));
}

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

        const auto seqBase = mpcd::run_zone_pass(state0, params, "base", 88172645463325252ULL);
        const auto seqShift = mpcd::run_zone_pass(seqBase.stateOut, params, "shifted", 998244353ULL);

        const auto ompBase = mpcd::run_zone_pass_openmp(state0, params, "base", 88172645463325252ULL, nthreads);
        const auto ompShift = mpcd::run_zone_pass_openmp(ompBase.stateOut, params, "shifted", 998244353ULL, nthreads);

        mpcd::write_xy_interleaved(out_prefix + "_seq_after_base_x.bin", seqBase.stateOut.x, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_seq_after_base_v.bin", seqBase.stateOut.v, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_omp_after_base_x.bin", ompBase.stateOut.x, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_omp_after_base_v.bin", ompBase.stateOut.v, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_seq_x.bin", seqShift.stateOut.x, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_seq_v.bin", seqShift.stateOut.v, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_omp_x.bin", ompShift.stateOut.x, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_omp_v.bin", ompShift.stateOut.v, params.n);
        if (has_type) {
            mpcd::write_u8(out_prefix + "_seq_type.bin", seqShift.stateOut.type, params.n);
            mpcd::write_u8(out_prefix + "_omp_type.bin", ompShift.stateOut.type, params.n);
        }
        if (has_r0) {
            mpcd::write_xy_interleaved(out_prefix + "_seq_r0.bin", seqShift.stateOut.r0, params.n);
            mpcd::write_xy_interleaved(out_prefix + "_omp_r0.bin", ompShift.stateOut.r0, params.n);
        }
        mpcd::write_i32_grid_bin(out_prefix + "_zone_owner_base.bin", params.Nx, params.Ny, ompBase.zoneOwnerMap);
        mpcd::write_i32_grid_bin(out_prefix + "_zone_owner_shifted.bin", params.Nx, params.Ny, ompShift.zoneOwnerMap);

        std::ofstream fout(out_prefix + "_runout.kv");
        if (!fout) throw std::runtime_error("Cannot open runout file for writing");
        fout << "nThreadsRequested=" << ompShift.metrics.nThreadsRequested << '\n';
        fout << "nThreadsUsed=" << ompShift.metrics.nThreadsUsed << '\n';
        fout << "nZonesBase=" << ompBase.metrics.nZones << '\n';
        fout << "nZonesShifted=" << ompShift.metrics.nZones << '\n';
        fout << "seq_base_nParticlesMovedDense=" << seqBase.metrics.nParticlesMovedDense << '\n';
        fout << "seq_base_nParticlesMovedSparse=" << seqBase.metrics.nParticlesMovedSparse << '\n';
        fout << "omp_base_nParticlesMovedDense=" << ompBase.metrics.nParticlesMovedDense << '\n';
        fout << "omp_base_nParticlesMovedSparse=" << ompBase.metrics.nParticlesMovedSparse << '\n';
        fout << "seq_shifted_nParticlesMovedDense=" << seqShift.metrics.nParticlesMovedDense << '\n';
        fout << "seq_shifted_nParticlesMovedSparse=" << seqShift.metrics.nParticlesMovedSparse << '\n';
        fout << "omp_shifted_nParticlesMovedDense=" << ompShift.metrics.nParticlesMovedDense << '\n';
        fout << "omp_shifted_nParticlesMovedSparse=" << ompShift.metrics.nParticlesMovedSparse << '\n';
        fout << "seq_base_corrRmsDU=" << seqBase.metrics.corrRmsDU << '\n';
        fout << "omp_base_corrRmsDU=" << ompBase.metrics.corrRmsDU << '\n';
        fout << "seq_base_corrMaxDU=" << seqBase.metrics.corrMaxDU << '\n';
        fout << "omp_base_corrMaxDU=" << ompBase.metrics.corrMaxDU << '\n';
        fout << "seq_shifted_corrRmsDU=" << seqShift.metrics.corrRmsDU << '\n';
        fout << "omp_shifted_corrRmsDU=" << ompShift.metrics.corrRmsDU << '\n';
        fout << "seq_shifted_corrMaxDU=" << seqShift.metrics.corrMaxDU << '\n';
        fout << "omp_shifted_corrMaxDU=" << ompShift.metrics.corrMaxDU << '\n';
        fout << "meanAbsDxAfterBase=" << mean_abs_xy_diff(seqBase.stateOut.x, ompBase.stateOut.x, params.n, 0) << '\n';
        fout << "meanAbsDyAfterBase=" << mean_abs_xy_diff(seqBase.stateOut.x, ompBase.stateOut.x, params.n, 1) << '\n';
        fout << "meanAbsDvxAfterBase=" << mean_abs_xy_diff(seqBase.stateOut.v, ompBase.stateOut.v, params.n, 0) << '\n';
        fout << "meanAbsDvyAfterBase=" << mean_abs_xy_diff(seqBase.stateOut.v, ompBase.stateOut.v, params.n, 1) << '\n';
        fout << "meanAbsDxFinal=" << mean_abs_xy_diff(seqShift.stateOut.x, ompShift.stateOut.x, params.n, 0) << '\n';
        fout << "meanAbsDyFinal=" << mean_abs_xy_diff(seqShift.stateOut.x, ompShift.stateOut.x, params.n, 1) << '\n';
        fout << "meanAbsDvxFinal=" << mean_abs_xy_diff(seqShift.stateOut.v, ompShift.stateOut.v, params.n, 0) << '\n';
        fout << "meanAbsDvyFinal=" << mean_abs_xy_diff(seqShift.stateOut.v, ompShift.stateOut.v, params.n, 1) << '\n';
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "Fatal error: " << e.what() << '\n';
        return 1;
    }
}
