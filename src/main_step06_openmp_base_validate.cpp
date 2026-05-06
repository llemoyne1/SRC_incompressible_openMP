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

        const auto seq = mpcd::run_zone_pass(state0, params, "base", 88172645463325252ULL);
        const auto ompRes = mpcd::run_zone_pass_openmp_base(state0, params, 88172645463325252ULL, nthreads);

        mpcd::write_xy_interleaved(out_prefix + "_seq_x.bin", seq.stateOut.x, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_seq_v.bin", seq.stateOut.v, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_omp_x.bin", ompRes.stateOut.x, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_omp_v.bin", ompRes.stateOut.v, params.n);
        if (has_type) {
            mpcd::write_u8(out_prefix + "_seq_type.bin", seq.stateOut.type, params.n);
            mpcd::write_u8(out_prefix + "_omp_type.bin", ompRes.stateOut.type, params.n);
        }
        if (has_r0) {
            mpcd::write_xy_interleaved(out_prefix + "_seq_r0.bin", seq.stateOut.r0, params.n);
            mpcd::write_xy_interleaved(out_prefix + "_omp_r0.bin", ompRes.stateOut.r0, params.n);
        }
        mpcd::write_i32_grid_bin(out_prefix + "_zone_owner_base.bin", params.Nx, params.Ny, ompRes.zoneOwnerMap);

        std::ofstream fout(out_prefix + "_runout.kv");
        if (!fout) throw std::runtime_error("Cannot open runout file for writing");
        fout << "nThreadsRequested=" << ompRes.metrics.nThreadsRequested << '\n';
        fout << "nThreadsUsed=" << ompRes.metrics.nThreadsUsed << '\n';
        fout << "nZones=" << ompRes.metrics.nZones << '\n';
        fout << "seq_nParticlesMovedDense=" << seq.metrics.nParticlesMovedDense << '\n';
        fout << "seq_nParticlesMovedSparse=" << seq.metrics.nParticlesMovedSparse << '\n';
        fout << "omp_nParticlesMovedDense=" << ompRes.metrics.nParticlesMovedDense << '\n';
        fout << "omp_nParticlesMovedSparse=" << ompRes.metrics.nParticlesMovedSparse << '\n';
        fout << "seq_corrRmsDU=" << seq.metrics.corrRmsDU << '\n';
        fout << "omp_corrRmsDU=" << ompRes.metrics.corrRmsDU << '\n';
        fout << "seq_corrMaxDU=" << seq.metrics.corrMaxDU << '\n';
        fout << "omp_corrMaxDU=" << ompRes.metrics.corrMaxDU << '\n';
        fout << "meanAbsDx=" << mean_abs_xy_diff(seq.stateOut.x, ompRes.stateOut.x, params.n, 0) << '\n';
        fout << "meanAbsDy=" << mean_abs_xy_diff(seq.stateOut.x, ompRes.stateOut.x, params.n, 1) << '\n';
        fout << "meanAbsDvx=" << mean_abs_xy_diff(seq.stateOut.v, ompRes.stateOut.v, params.n, 0) << '\n';
        fout << "meanAbsDvy=" << mean_abs_xy_diff(seq.stateOut.v, ompRes.stateOut.v, params.n, 1) << '\n';
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "Fatal error: " << e.what() << '\n';
        return 1;
    }
}
