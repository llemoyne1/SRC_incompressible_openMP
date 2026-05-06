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

static void write_closure_prefixed(std::ofstream& fout, const std::string& prefix, const mpcd::LiquidClosureMetrics& m) {
    fout << prefix << "betaRepairOpt=" << m.betaRepairOpt << '\n';
    fout << prefix << "betaRepairApplied=" << m.betaRepairApplied << '\n';
    fout << prefix << "betaEOSApplied=" << m.betaEOSApplied << '\n';
    fout << prefix << "meanPdriveRaw=" << m.meanPdriveRaw << '\n';
    fout << prefix << "meanPdrive=" << m.meanPdrive << '\n';
    fout << prefix << "rmsRepairDU=" << m.rmsRepairDU << '\n';
    fout << prefix << "maxRepairDU=" << m.maxRepairDU << '\n';
    fout << prefix << "rmsEOSDU=" << m.rmsEOSDU << '\n';
    fout << prefix << "maxEOSDU=" << m.maxEOSDU << '\n';
    fout << prefix << "momentumDeltaX=" << m.momentumDeltaX << '\n';
    fout << prefix << "momentumDeltaY=" << m.momentumDeltaY << '\n';
    fout << prefix << "nMaskedInterzoneCells=" << m.nMaskedInterzoneCells << '\n';
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
        mpcd::State state0 = mpcd::read_state(x_path, v_path, type_path, r0_path, has_type, has_r0, params.n);

        // Step 1: streaming + forcing + boundary conditions + collision
        mpcd::State stateRef = state0;
        for (int i = 0; i < params.n; ++i) {
            stateRef.v[2 * i] += params.bodyForceX * params.dt;
            stateRef.v[2 * i + 1] += params.g * params.dt;
            stateRef.x[2 * i] += params.dt * stateRef.v[2 * i];
            stateRef.x[2 * i + 1] += params.dt * stateRef.v[2 * i + 1];
        }

        mpcd::WallInfo wallInfo;
        mpcd::apply_bc_general(stateRef.x, stateRef.v, params, wallInfo, 104729ULL);
        const double pBotInst = wallInfo.dPyBot / std::max(params.Lx * params.dt, 1e-30);
        const double pTopInst = wallInfo.dPyTop / std::max(params.Lx * params.dt, 1e-30);
        const double pMeanInst = 0.5 * (pBotInst + pTopInst);

        const auto cid = mpcd::srd_cell_id_with_random_shift(stateRef.x, params, 130363ULL);
        mpcd::srd_collision_step(stateRef.v, cid, params, 433494437ULL);

        // Step 3: base then shifted redistribution
        const auto baseResult = mpcd::run_zone_pass(stateRef, params, "base", 88172645463325252ULL);
        const auto shiftedResult = mpcd::run_zone_pass(baseResult.stateOut, params, "shifted", 88172645463325252ULL + 4099ULL);

        // Step 4: liquid closure using ref / red
        const auto closureResult = mpcd::run_liquid_closure(stateRef, shiftedResult.stateOut, params);

        // Dumps: ref state
        mpcd::write_xy_interleaved(out_prefix + "_ref_x.bin", stateRef.x, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_ref_v.bin", stateRef.v, params.n);
        if (has_type) mpcd::write_u8(out_prefix + "_ref_type.bin", stateRef.type, params.n);
        if (has_r0) mpcd::write_xy_interleaved(out_prefix + "_ref_r0.bin", stateRef.r0, params.n);

        // Dumps: after base
        mpcd::write_xy_interleaved(out_prefix + "_after_base_x.bin", baseResult.stateOut.x, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_after_base_v.bin", baseResult.stateOut.v, params.n);
        if (has_type) mpcd::write_u8(out_prefix + "_after_base_type.bin", baseResult.stateOut.type, params.n);
        if (has_r0) mpcd::write_xy_interleaved(out_prefix + "_after_base_r0.bin", baseResult.stateOut.r0, params.n);

        // Dumps: red (after shifted)
        mpcd::write_xy_interleaved(out_prefix + "_red_x.bin", shiftedResult.stateOut.x, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_red_v.bin", shiftedResult.stateOut.v, params.n);
        if (has_type) mpcd::write_u8(out_prefix + "_red_type.bin", shiftedResult.stateOut.type, params.n);
        if (has_r0) mpcd::write_xy_interleaved(out_prefix + "_red_r0.bin", shiftedResult.stateOut.r0, params.n);

        // Dumps: final out
        mpcd::write_xy_interleaved(out_prefix + "_x.bin", closureResult.stateOut.x, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_v.bin", closureResult.stateOut.v, params.n);
        if (has_type) mpcd::write_u8(out_prefix + "_type.bin", closureResult.stateOut.type, params.n);
        if (has_r0) mpcd::write_xy_interleaved(out_prefix + "_r0.bin", closureResult.stateOut.r0, params.n);

        // Cell fields and zone maps
        mpcd::write_cell_fields_bin(out_prefix + "_cellfields_ref.bin", baseResult.beforeFields);
        mpcd::write_cell_fields_bin(out_prefix + "_cellfields_after_base.bin", baseResult.afterFields);
        mpcd::write_cell_fields_bin(out_prefix + "_cellfields_before_shifted.bin", shiftedResult.beforeFields);
        mpcd::write_cell_fields_bin(out_prefix + "_cellfields_red.bin", shiftedResult.afterFields);
        mpcd::write_cell_fields_bin(out_prefix + "_cellfields_repaired.bin", closureResult.repairedFields);
        mpcd::write_cell_fields_bin(out_prefix + "_cellfields_out.bin", closureResult.outFields);
        mpcd::write_i32_grid_bin(out_prefix + "_zone_owner_base.bin", params.Nx, params.Ny, baseResult.zoneOwnerMap);
        mpcd::write_i32_grid_bin(out_prefix + "_zone_owner_shifted.bin", params.Nx, params.Ny, shiftedResult.zoneOwnerMap);

        // Closure fields
        mpcd::write_f64_grid_bin(out_prefix + "_pdrive_raw.bin", params.Nx, params.Ny, closureResult.pdriveRaw);
        mpcd::write_f64_grid_bin(out_prefix + "_pdrive.bin", params.Nx, params.Ny, closureResult.pdrive);
        mpcd::write_f64_grid_bin(out_prefix + "_durepairx.bin", params.Nx, params.Ny, closureResult.duRepairX);
        mpcd::write_f64_grid_bin(out_prefix + "_durepairy.bin", params.Nx, params.Ny, closureResult.duRepairY);
        mpcd::write_f64_grid_bin(out_prefix + "_dueosx.bin", params.Nx, params.Ny, closureResult.duEOSX);
        mpcd::write_f64_grid_bin(out_prefix + "_dueosy.bin", params.Nx, params.Ny, closureResult.duEOSY);
        mpcd::write_i32_grid_bin_lc(out_prefix + "_interzone_mask.bin", params.Nx, params.Ny, closureResult.interzoneMask);

        std::ofstream fout(out_prefix + "_runout.kv");
        if (!fout) throw std::runtime_error("Cannot open runout file for writing");
        fout << "inputTag=" << x_path << '\n';
        fout << "outputTag=" << out_prefix << '\n';
        fout << "pBotInst=" << pBotInst << '\n';
        fout << "pTopInst=" << pTopInst << '\n';
        fout << "pMeanInst=" << pMeanInst << '\n';
        write_metrics_prefixed(fout, "base_", baseResult.metrics);
        write_metrics_prefixed(fout, "shifted_", shiftedResult.metrics);
        write_closure_prefixed(fout, "closure_", closureResult.metrics);
        fout << "finalOccStd=" << shiftedResult.metrics.occStdAfter << '\n';
        fout << "finalOutBand=" << shiftedResult.metrics.outBandAfter << '\n';
        fout << "totalParticlesMovedDense=" << (baseResult.metrics.nParticlesMovedDense + shiftedResult.metrics.nParticlesMovedDense) << '\n';
        fout << "totalParticlesMovedSparse=" << (baseResult.metrics.nParticlesMovedSparse + shiftedResult.metrics.nParticlesMovedSparse) << '\n';
        fout << "meanVelocityInX=" << mean_component(state0.v, 0, params.n) << '\n';
        fout << "meanVelocityInY=" << mean_component(state0.v, 1, params.n) << '\n';
        fout << "meanVelocityRefX=" << mean_component(stateRef.v, 0, params.n) << '\n';
        fout << "meanVelocityRefY=" << mean_component(stateRef.v, 1, params.n) << '\n';
        fout << "meanVelocityBaseX=" << mean_component(baseResult.stateOut.v, 0, params.n) << '\n';
        fout << "meanVelocityBaseY=" << mean_component(baseResult.stateOut.v, 1, params.n) << '\n';
        fout << "meanVelocityRedX=" << mean_component(shiftedResult.stateOut.v, 0, params.n) << '\n';
        fout << "meanVelocityRedY=" << mean_component(shiftedResult.stateOut.v, 1, params.n) << '\n';
        fout << "meanVelocityOutX=" << mean_component(closureResult.stateOut.v, 0, params.n) << '\n';
        fout << "meanVelocityOutY=" << mean_component(closureResult.stateOut.v, 1, params.n) << '\n';
        fout << "meanKineticIn=" << mean_kinetic(state0.v, params.n) << '\n';
        fout << "meanKineticRef=" << mean_kinetic(stateRef.v, params.n) << '\n';
        fout << "meanKineticBase=" << mean_kinetic(baseResult.stateOut.v, params.n) << '\n';
        fout << "meanKineticRed=" << mean_kinetic(shiftedResult.stateOut.v, params.n) << '\n';
        fout << "meanKineticOut=" << mean_kinetic(closureResult.stateOut.v, params.n) << '\n';
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "Fatal error: " << e.what() << '\n';
        return 1;
    }
}
