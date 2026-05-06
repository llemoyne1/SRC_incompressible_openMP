#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <string>

#include "boundary_conditions.h"
#include "common_grid.h"
#include "dump_io.h"
#include "params_io.h"
#include "srd_collision.h"
#include "state_io.h"
#include "types.h"

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
        mpcd::Params params = mpcd::read_params_kv(params_path);
        mpcd::State state = mpcd::read_state(x_path, v_path, type_path, r0_path, has_type, has_r0, params.n);

        for (int i = 0; i < params.n; ++i) {
            state.v[2 * i] += params.bodyForceX * params.dt;
            state.v[2 * i + 1] += params.g * params.dt;
            state.x[2 * i] += params.dt * state.v[2 * i];
            state.x[2 * i + 1] += params.dt * state.v[2 * i + 1];
        }

        mpcd::WallInfo wallInfo;
        mpcd::apply_bc_general(state.x, state.v, params, wallInfo, 104729ULL);

        const double pBotInst = wallInfo.dPyBot / std::max(params.Lx * params.dt, 1e-30);
        const double pTopInst = wallInfo.dPyTop / std::max(params.Lx * params.dt, 1e-30);
        const double pMeanInst = 0.5 * (pBotInst + pTopInst);

        const auto cid = mpcd::srd_cell_id_with_random_shift(state.x, params, 130363ULL);
        mpcd::srd_collision_step(state.v, cid, params, 433494437ULL);

        const double dx = params.Lx / static_cast<double>(params.Nx);
        const double dy = params.Ly / static_cast<double>(params.Ny);
        const double Vc = dx * dy;
        const double rhoTargetScalar = params.gamma / Vc;
        const mpcd::CellFields G = mpcd::compute_cell_fields(state.x, state.v, params, rhoTargetScalar);

        mpcd::write_xy_interleaved(out_prefix + "_x.bin", state.x, params.n);
        mpcd::write_xy_interleaved(out_prefix + "_v.bin", state.v, params.n);
        if (has_type) {
            mpcd::write_u8(out_prefix + "_type.bin", state.type, params.n);
        }
        if (has_r0) {
            mpcd::write_xy_interleaved(out_prefix + "_r0.bin", state.r0, params.n);
        }
        mpcd::write_cell_fields_bin(out_prefix + "_cellfields.bin", G);

        mpcd::RunOutStep runout{};
        runout.inputTag = x_path;
        runout.outputTag = out_prefix;
        runout.pBotInst = pBotInst;
        runout.pTopInst = pTopInst;
        runout.pMeanInst = pMeanInst;
        runout.layoutMode = "none";
        runout.nZonesExecuted = 0;
        mpcd::write_runout_kv(out_prefix + "_runout.kv", runout);

        return 0;
    } catch (const std::exception& e) {
        std::cerr << "Fatal error: " << e.what() << '\n';
        return 1;
    }
}
