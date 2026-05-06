#include <fstream>
#include <iostream>
#include <cmath>
#include <stdexcept>
#include <string>

#include "dump_io.h"
#include "params_io.h"
#include "state_io.h"
#include "types.h"
#include "zone_pass.h"

static void write_metrics_prefixed(std::ofstream& fout, const std::string& prefix, const mpcd::ZonePassMetrics& m) {
    fout << prefix << "layoutMode=" << m.layoutMode << '\n';
    fout << prefix << "nZonesExecuted=" << m.nZonesExecuted << '\n';
    fout << prefix << "occStdBefore=" << m.occStdBefore << '\n';
    fout << prefix << "occStdAfter=" << m.occStdAfter << '\n';
    fout << prefix << "outBandBefore=" << m.outBandBefore << '\n';
    fout << prefix << "outBandAfter=" << m.outBandAfter << '\n';
    fout << prefix << "nDenseBefore=" << m.nDenseBefore << '\n';
    fout << prefix << "nDenseAfter=" << m.nDenseAfter << '\n';
    fout << prefix << "nSparseBefore=" << m.nSparseBefore << '\n';
    fout << prefix << "nSparseAfter=" << m.nSparseAfter << '\n';
    fout << prefix << "nEmptyActiveBefore=" << m.nEmptyActiveBefore << '\n';
    fout << prefix << "nEmptyActiveAfter=" << m.nEmptyActiveAfter << '\n';
    fout << prefix << "nParticlesMovedDense=" << m.nParticlesMovedDense << '\n';
    fout << prefix << "nParticlesMovedSparse=" << m.nParticlesMovedSparse << '\n';
    fout << prefix << "corrRmsDU=" << m.corrRmsDU << '\n';
    fout << prefix << "corrMaxDU=" << m.corrMaxDU << '\n';
    fout << prefix << "momentumDeltaX=" << m.momentumDeltaX << '\n';
    fout << prefix << "momentumDeltaY=" << m.momentumDeltaY << '\n';
}

int main(int argc, char** argv) {
    if (argc != 9) {
        std::cerr << "Usage: " << argv[0]
                  << " params.kv state_x.bin state_v.bin state_type.bin state_r0.bin out_prefix has_type has_r0\n";
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

    try {
        const mpcd::Params params = mpcd::read_params_kv(params_path);
        const mpcd::State state = mpcd::read_state(x_path, v_path, type_path, r0_path, has_type, has_r0, params.n);

        const auto baseResult = mpcd::run_zone_pass(state, params, "base", 88172645463325252ULL);
        mpcd::write_xy_interleaved(out_prefix + "_after_base_x.bin", baseResult.stateOut.x, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_after_base_v.bin", baseResult.stateOut.v, params.n);
        if (has_type) {
            mpcd::write_u8(out_prefix + "_after_base_type.bin", baseResult.stateOut.type, params.n);
        }
        if (has_r0) {
            mpcd::write_xy_interleaved(out_prefix + "_after_base_r0.bin", baseResult.stateOut.r0, params.n);
        }
        mpcd::write_cell_fields_bin(out_prefix + "_cellfields_before_base.bin", baseResult.beforeFields);
        mpcd::write_cell_fields_bin(out_prefix + "_cellfields_after_base.bin", baseResult.afterFields);
        mpcd::write_i32_grid_bin(out_prefix + "_zone_owner_base.bin", params.Nx, params.Ny, baseResult.zoneOwnerMap);

        const auto shiftedResult = mpcd::run_zone_pass(baseResult.stateOut, params, "shifted", 88172645463325252ULL + 4099ULL);
        mpcd::write_xy_interleaved(out_prefix + "_x.bin", shiftedResult.stateOut.x, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_v.bin", shiftedResult.stateOut.v, params.n);
        if (has_type) {
            mpcd::write_u8(out_prefix + "_type.bin", shiftedResult.stateOut.type, params.n);
        }
        if (has_r0) {
            mpcd::write_xy_interleaved(out_prefix + "_r0.bin", shiftedResult.stateOut.r0, params.n);
        }
        mpcd::write_cell_fields_bin(out_prefix + "_cellfields_before_shifted.bin", shiftedResult.beforeFields);
        mpcd::write_cell_fields_bin(out_prefix + "_cellfields_after_shifted.bin", shiftedResult.afterFields);
        mpcd::write_i32_grid_bin(out_prefix + "_zone_owner_shifted.bin", params.Nx, params.Ny, shiftedResult.zoneOwnerMap);

        std::ofstream fout(out_prefix + "_runout.kv");
        if (!fout) {
            throw std::runtime_error("Cannot open runout file for writing");
        }
        fout << "inputTag=" << x_path << '\n';
        fout << "outputTag=" << out_prefix << '\n';
        write_metrics_prefixed(fout, "base_", baseResult.metrics);
        write_metrics_prefixed(fout, "shifted_", shiftedResult.metrics);
        fout << "finalOccStd=" << shiftedResult.metrics.occStdAfter << '\n';
        fout << "finalOutBand=" << shiftedResult.metrics.outBandAfter << '\n';
        fout << "totalParticlesMovedDense=" << (baseResult.metrics.nParticlesMovedDense + shiftedResult.metrics.nParticlesMovedDense) << '\n';
        fout << "totalParticlesMovedSparse=" << (baseResult.metrics.nParticlesMovedSparse + shiftedResult.metrics.nParticlesMovedSparse) << '\n';
        fout << "totalCorrRmsDU=" << std::sqrt(0.5*(baseResult.metrics.corrRmsDU*baseResult.metrics.corrRmsDU + shiftedResult.metrics.corrRmsDU*shiftedResult.metrics.corrRmsDU)) << '\n';
        fout << "totalCorrMaxDU=" << std::max(baseResult.metrics.corrMaxDU, shiftedResult.metrics.corrMaxDU) << '\n';
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "Fatal error: " << e.what() << '\n';
        return 1;
    }
}
