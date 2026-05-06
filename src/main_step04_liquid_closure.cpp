#include <algorithm>
#include <cmath>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>

#include "dump_io.h"
#include "liquid_closure.h"
#include "params_io.h"
#include "state_io.h"
#include "types.h"

static double mean_component(const std::vector<double>& a, int comp, int n) {
    double s = 0.0;
    for (int i = 0; i < n; ++i) s += a[2 * i + comp];
    return s / static_cast<double>(std::max(n, 1));
}

static double mean_kinetic(const std::vector<double>& v, int n) {
    double s = 0.0;
    for (int i = 0; i < n; ++i) {
        s += 0.5 * (v[2 * i] * v[2 * i] + v[2 * i + 1] * v[2 * i + 1]);
    }
    return s / static_cast<double>(std::max(n, 1));
}

int main(int argc, char** argv) {
    if (argc != 12) {
        std::cerr << "Usage: " << argv[0]
                  << " params.kv ref_x.bin ref_v.bin red_x.bin red_v.bin ref_type.bin ref_r0.bin out_prefix has_type has_r0 copy_type_from_ref\n";
        return 2;
    }

    const std::string params_path = argv[1];
    const std::string ref_x_path = argv[2];
    const std::string ref_v_path = argv[3];
    const std::string red_x_path = argv[4];
    const std::string red_v_path = argv[5];
    const std::string type_path = argv[6];
    const std::string r0_path = argv[7];
    const std::string out_prefix = argv[8];
    const bool has_type = std::string(argv[9]) == "1";
    const bool has_r0 = std::string(argv[10]) == "1";
    (void)argv[11];

    try {
        const mpcd::Params params = mpcd::read_params_kv(params_path);
        const auto stateRef = mpcd::read_state(ref_x_path, ref_v_path, type_path, r0_path, has_type, has_r0, params.n);
        mpcd::State stateRed = mpcd::read_state(red_x_path, red_v_path, type_path, r0_path, has_type, has_r0, params.n);
        if (has_type) stateRed.type = stateRef.type;
        if (has_r0) stateRed.r0 = stateRef.r0;

        const auto result = mpcd::run_liquid_closure(stateRef, stateRed, params);

        mpcd::write_xy_interleaved(out_prefix + "_x.bin", result.stateOut.x, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_v.bin", result.stateOut.v, params.n);
        if (has_type) mpcd::write_u8(out_prefix + "_type.bin", result.stateOut.type, params.n);
        if (has_r0) mpcd::write_xy_interleaved(out_prefix + "_r0.bin", result.stateOut.r0, params.n);

        mpcd::write_cell_fields_bin(out_prefix + "_cellfields_ref.bin", result.refFields);
        mpcd::write_cell_fields_bin(out_prefix + "_cellfields_red.bin", result.redFields);
        mpcd::write_cell_fields_bin(out_prefix + "_cellfields_repaired.bin", result.repairedFields);
        mpcd::write_cell_fields_bin(out_prefix + "_cellfields_out.bin", result.outFields);
        mpcd::write_f64_grid_bin(out_prefix + "_pdrive_raw.bin", params.Nx, params.Ny, result.pdriveRaw);
        mpcd::write_f64_grid_bin(out_prefix + "_pdrive.bin", params.Nx, params.Ny, result.pdrive);
        mpcd::write_f64_grid_bin(out_prefix + "_durepairx.bin", params.Nx, params.Ny, result.duRepairX);
        mpcd::write_f64_grid_bin(out_prefix + "_durepairy.bin", params.Nx, params.Ny, result.duRepairY);
        mpcd::write_f64_grid_bin(out_prefix + "_dueosx.bin", params.Nx, params.Ny, result.duEOSX);
        mpcd::write_f64_grid_bin(out_prefix + "_dueosy.bin", params.Nx, params.Ny, result.duEOSY);
        mpcd::write_i32_grid_bin_lc(out_prefix + "_interzone_mask.bin", params.Nx, params.Ny, result.interzoneMask);

        std::ofstream fout(out_prefix + "_runout.kv");
        if (!fout) throw std::runtime_error("Cannot open runout file for writing");
        fout << "inputRefTag=" << ref_x_path << '\n';
        fout << "inputRedTag=" << red_x_path << '\n';
        fout << "outputTag=" << out_prefix << '\n';
        fout << "betaRepairOpt=" << result.metrics.betaRepairOpt << '\n';
        fout << "betaRepairApplied=" << result.metrics.betaRepairApplied << '\n';
        fout << "betaEOSApplied=" << result.metrics.betaEOSApplied << '\n';
        fout << "meanPdriveRaw=" << result.metrics.meanPdriveRaw << '\n';
        fout << "meanPdrive=" << result.metrics.meanPdrive << '\n';
        fout << "rmsRepairDU=" << result.metrics.rmsRepairDU << '\n';
        fout << "maxRepairDU=" << result.metrics.maxRepairDU << '\n';
        fout << "rmsEOSDU=" << result.metrics.rmsEOSDU << '\n';
        fout << "maxEOSDU=" << result.metrics.maxEOSDU << '\n';
        fout << "momentumDeltaX=" << result.metrics.momentumDeltaX << '\n';
        fout << "momentumDeltaY=" << result.metrics.momentumDeltaY << '\n';
        fout << "nMaskedInterzoneCells=" << result.metrics.nMaskedInterzoneCells << '\n';
        fout << "meanVelocityRefX=" << mean_component(stateRef.v, 0, params.n) << '\n';
        fout << "meanVelocityRefY=" << mean_component(stateRef.v, 1, params.n) << '\n';
        fout << "meanVelocityRedX=" << mean_component(stateRed.v, 0, params.n) << '\n';
        fout << "meanVelocityRedY=" << mean_component(stateRed.v, 1, params.n) << '\n';
        fout << "meanVelocityOutX=" << mean_component(result.stateOut.v, 0, params.n) << '\n';
        fout << "meanVelocityOutY=" << mean_component(result.stateOut.v, 1, params.n) << '\n';
        fout << "meanKineticRef=" << mean_kinetic(stateRef.v, params.n) << '\n';
        fout << "meanKineticRed=" << mean_kinetic(stateRed.v, params.n) << '\n';
        fout << "meanKineticOut=" << mean_kinetic(result.stateOut.v, params.n) << '\n';
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "Fatal error: " << e.what() << '\n';
        return 1;
    }
}
