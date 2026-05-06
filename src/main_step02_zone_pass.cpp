#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>

#include "dump_io.h"
#include "params_io.h"
#include "state_io.h"
#include "types.h"
#include "zone_pass.h"

int main(int argc, char** argv) {
    if (argc != 10) {
        std::cerr << "Usage: " << argv[0]
                  << " params.kv state_x.bin state_v.bin state_type.bin state_r0.bin out_prefix layout_mode has_type has_r0\n";
        return 2;
    }

    const std::string params_path = argv[1];
    const std::string x_path = argv[2];
    const std::string v_path = argv[3];
    const std::string type_path = argv[4];
    const std::string r0_path = argv[5];
    const std::string out_prefix = argv[6];
    const std::string layout_mode = argv[7];
    const bool has_type = std::string(argv[8]) == "1";
    const bool has_r0 = std::string(argv[9]) == "1";

    try {
        const mpcd::Params params = mpcd::read_params_kv(params_path);
        const mpcd::State state = mpcd::read_state(x_path, v_path, type_path, r0_path, has_type, has_r0, params.n);
        const auto result = mpcd::run_zone_pass(state, params, layout_mode, 88172645463325252ULL);

        mpcd::write_xy_interleaved(out_prefix + "_x.bin", result.stateOut.x, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_v.bin", result.stateOut.v, params.n);
        if (has_type) {
            mpcd::write_u8(out_prefix + "_type.bin", result.stateOut.type, params.n);
        }
        if (has_r0) {
            mpcd::write_xy_interleaved(out_prefix + "_r0.bin", result.stateOut.r0, params.n);
        }

        mpcd::write_cell_fields_bin(out_prefix + "_cellfields_before.bin", result.beforeFields);
        mpcd::write_cell_fields_bin(out_prefix + "_cellfields_after.bin", result.afterFields);
        mpcd::write_i32_grid_bin(out_prefix + "_zone_owner.bin", params.Nx, params.Ny, result.zoneOwnerMap);

        std::ofstream fout(out_prefix + "_runout.kv");
        if (!fout) {
            throw std::runtime_error("Cannot open runout file for writing");
        }
        fout << "inputTag=" << x_path << '\n';
        fout << "outputTag=" << out_prefix << '\n';
        fout << "layoutMode=" << result.metrics.layoutMode << '\n';
        fout << "nZonesExecuted=" << result.metrics.nZonesExecuted << '\n';
        fout << "occStdBefore=" << result.metrics.occStdBefore << '\n';
        fout << "occStdAfter=" << result.metrics.occStdAfter << '\n';
        fout << "outBandBefore=" << result.metrics.outBandBefore << '\n';
        fout << "outBandAfter=" << result.metrics.outBandAfter << '\n';
        fout << "nDenseBefore=" << result.metrics.nDenseBefore << '\n';
        fout << "nDenseAfter=" << result.metrics.nDenseAfter << '\n';
        fout << "nSparseBefore=" << result.metrics.nSparseBefore << '\n';
        fout << "nSparseAfter=" << result.metrics.nSparseAfter << '\n';
        fout << "nEmptyActiveBefore=" << result.metrics.nEmptyActiveBefore << '\n';
        fout << "nEmptyActiveAfter=" << result.metrics.nEmptyActiveAfter << '\n';
        fout << "nParticlesMovedDense=" << result.metrics.nParticlesMovedDense << '\n';
        fout << "nParticlesMovedSparse=" << result.metrics.nParticlesMovedSparse << '\n';
        fout << "corrRmsDU=" << result.metrics.corrRmsDU << '\n';
        fout << "corrMaxDU=" << result.metrics.corrMaxDU << '\n';
        fout << "momentumDeltaX=" << result.metrics.momentumDeltaX << '\n';
        fout << "momentumDeltaY=" << result.metrics.momentumDeltaY << '\n';
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "Fatal error: " << e.what() << '\n';
        return 1;
    }
}
