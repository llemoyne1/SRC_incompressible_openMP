#include <algorithm>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>

#include "boundary_conditions.h"
#include "common_grid.h"
#include "dump_io.h"
#include "liquid_closure.h"
#include "params_io.h"
#include "srd_collision.h"
#include "state_io.h"
#include "types.h"
#include "zone_pass.h"

namespace {

using namespace mpcd;

std::string trim(const std::string& s) {
    std::size_t b = 0;
    while (b < s.size() && std::isspace(static_cast<unsigned char>(s[b]))) ++b;
    std::size_t e = s.size();
    while (e > b && std::isspace(static_cast<unsigned char>(s[e - 1]))) --e;
    return s.substr(b, e - b);
}

std::unordered_map<std::string, std::string> read_kv_map(const std::string& filepath) {
    std::ifstream fin(filepath);
    if (!fin) throw std::runtime_error("Cannot open params file: " + filepath);
    std::unordered_map<std::string, std::string> kv;
    std::string line;
    while (std::getline(fin, line)) {
        line = trim(line);
        if (line.empty() || line[0] == '#') continue;
        const auto pos = line.find('=');
        if (pos == std::string::npos) throw std::runtime_error("Invalid key=value line: " + line);
        kv[trim(line.substr(0, pos))] = trim(line.substr(pos + 1));
    }
    return kv;
}

const std::string& require_key(const std::unordered_map<std::string, std::string>& kv, const std::string& key) {
    auto it = kv.find(key);
    if (it == kv.end()) throw std::runtime_error("Missing benchmark key: " + key);
    return it->second;
}

int parse_int(const std::string& s) { return std::stoi(s); }
double parse_double(const std::string& s) { return std::stod(s); }

std::vector<int> parse_steps_csv(const std::string& s) {
    std::vector<int> out;
    std::stringstream ss(s);
    std::string tok;
    while (std::getline(ss, tok, ',')) {
        tok = trim(tok);
        if (!tok.empty()) out.push_back(std::stoi(tok));
    }
    std::sort(out.begin(), out.end());
    out.erase(std::unique(out.begin(), out.end()), out.end());
    return out;
}

bool contains_step(const std::vector<int>& steps, int step) {
    return std::binary_search(steps.begin(), steps.end(), step);
}

double mean_component(const std::vector<double>& a, int comp, int n) {
    double s = 0.0;
    for (int i = 0; i < n; ++i) s += a[2 * i + comp];
    return s / static_cast<double>(std::max(n, 1));
}

double mean_kinetic(const std::vector<double>& v, int n) {
    double s = 0.0;
    for (int i = 0; i < n; ++i) s += 0.5 * (v[2*i]*v[2*i] + v[2*i+1]*v[2*i+1]);
    return s / static_cast<double>(std::max(n, 1));
}

double mean_field(const std::vector<double>& f) {
    if (f.empty()) return 0.0;
    double s = 0.0;
    for (double x : f) s += x;
    return s / static_cast<double>(f.size());
}

double flow_rate_qx(const CellFields& G, const Params& params) {
    return mean_field(G.Ux) * params.Ly;
}

double rho_target_scalar(const Params& params) {
    const double dx = params.Lx / static_cast<double>(params.Nx);
    const double dy = params.Ly / static_cast<double>(params.Ny);
    return params.gamma / (dx * dy);
}

void dump_state_prefix(const std::string& prefix, const State& s, int n, bool has_type, bool has_r0) {
    write_xy_interleaved(prefix + "_x.bin", s.x, n);
    write_xy_interleaved(prefix + "_v.bin", s.v, n);
    if (has_type) write_u8(prefix + "_type.bin", s.type, n);
    if (has_r0) write_xy_interleaved(prefix + "_r0.bin", s.r0, n);
}

void dump_snapshot(const std::string& out_prefix,
                   int step,
                   const State& state,
                   const CellFields& G,
                   int n,
                   bool has_type,
                   bool has_r0) {
    std::ostringstream oss;
    oss << out_prefix << "_step" << std::setw(4) << std::setfill('0') << step;
    const std::string prefix = oss.str();
    dump_state_prefix(prefix, state, n, has_type, has_r0);
    write_cell_fields_bin(prefix + "_cellfields.bin", G);
}

} // namespace

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
        const Params params = read_params_kv(params_path);
        const auto kv = read_kv_map(params_path);
        const int nSteps = parse_int(require_key(kv, "benchmark_nSteps"));
        const int metricsEvery = parse_int(require_key(kv, "benchmark_metricsEvery"));
        const std::vector<int> dumpSteps = parse_steps_csv(require_key(kv, "benchmark_dumpSteps"));

        State state = read_state(x_path, v_path, type_path, r0_path, has_type, has_r0, params.n);
        const double rhoTarget = rho_target_scalar(params);

        std::ofstream metrics(out_prefix + "_metrics.csv");
        if (!metrics) throw std::runtime_error("Cannot open metrics CSV for writing");
        metrics << "step,occStd,outBand,meanKinetic,meanUx,meanUy,Qx,baseOccStd,baseOutBand,shiftedOccStd,shiftedOutBand,meanPdrive,meanPdriveRaw,meanVelocityX,meanVelocityY,particlesMovedDense,particlesMovedSparse,betaRepairOpt,betaRepairApplied,betaRepairNum,betaRepairDen,rmsRepairDU,maxRepairDU,meanAbsRepairDU,nMaskedInterzoneCells,momentumDeltaX,momentumDeltaY\n";

        std::ofstream manifest(out_prefix + "_runout.kv");
        if (!manifest) throw std::runtime_error("Cannot open benchmark runout file");
        manifest << "inputTag=" << x_path << "\n";
        manifest << "outputTag=" << out_prefix << "\n";
        manifest << "benchmark_nSteps=" << nSteps << "\n";
        manifest << "benchmark_metricsEvery=" << metricsEvery << "\n";
        manifest << "benchmark_dumpSteps=" << require_key(kv, "benchmark_dumpSteps") << "\n";

        if (contains_step(dumpSteps, 0)) {
            const CellFields G0 = compute_cell_fields(state.x, state.v, params, rhoTarget);
            dump_snapshot(out_prefix, 0, state, G0, params.n, has_type, has_r0);
        }

        for (int step = 1; step <= nSteps; ++step) {
            State stateRef = state;
            for (int i = 0; i < params.n; ++i) {
                stateRef.v[2 * i] += params.bodyForceX * params.dt;
                stateRef.v[2 * i + 1] += params.g * params.dt;
                stateRef.x[2 * i] += params.dt * stateRef.v[2 * i];
                stateRef.x[2 * i + 1] += params.dt * stateRef.v[2 * i + 1];
            }
            WallInfo wallInfo;
            apply_bc_general(stateRef.x, stateRef.v, params, wallInfo, 104729ULL + 10007ULL * static_cast<std::uint64_t>(step));
            const auto cid = srd_cell_id_with_random_shift(stateRef.x, params, 130363ULL + 10007ULL * static_cast<std::uint64_t>(step));
            srd_collision_step(stateRef.v, cid, params, 433494437ULL + 10007ULL * static_cast<std::uint64_t>(step));

            const auto baseResult = run_zone_pass(stateRef, params, "base", 88172645463325252ULL + 10007ULL * static_cast<std::uint64_t>(step));
            const auto shiftedResult = run_zone_pass(baseResult.stateOut, params, "shifted", 88172645463325252ULL + 4099ULL + 10007ULL * static_cast<std::uint64_t>(step));
            const auto closureResult = run_liquid_closure(stateRef, shiftedResult.stateOut, params);
            state = closureResult.stateOut;

            if (metricsEvery > 0 && (step % metricsEvery == 0 || step == nSteps)) {
                metrics << step << ','
                        << shiftedResult.metrics.occStdAfter << ','
                        << shiftedResult.metrics.outBandAfter << ','
                        << mean_kinetic(state.v, params.n) << ','
                        << mean_field(closureResult.outFields.Ux) << ','
                        << mean_field(closureResult.outFields.Uy) << ','
                        << flow_rate_qx(closureResult.outFields, params) << ','
                        << baseResult.metrics.occStdAfter << ','
                        << baseResult.metrics.outBandAfter << ','
                        << shiftedResult.metrics.occStdAfter << ','
                        << shiftedResult.metrics.outBandAfter << ','
                        << closureResult.metrics.meanPdrive << ','
                        << closureResult.metrics.meanPdriveRaw << ','
                        << mean_component(state.v, 0, params.n) << ','
                        << mean_component(state.v, 1, params.n) << ','
                        << (baseResult.metrics.nParticlesMovedDense + shiftedResult.metrics.nParticlesMovedDense) << ','
                        << (baseResult.metrics.nParticlesMovedSparse + shiftedResult.metrics.nParticlesMovedSparse) << ','
                        << closureResult.metrics.betaRepairOpt << ','
                        << closureResult.metrics.betaRepairApplied << ','
                        << closureResult.metrics.betaRepairNum << ','
                        << closureResult.metrics.betaRepairDen << ','
                        << closureResult.metrics.rmsRepairDU << ','
                        << closureResult.metrics.maxRepairDU << ','
                        << closureResult.metrics.meanAbsRepairDU << ','
                        << closureResult.metrics.nMaskedInterzoneCells << ','
                        << closureResult.metrics.momentumDeltaX << ','
                        << closureResult.metrics.momentumDeltaY << '\n';
            }

            if (contains_step(dumpSteps, step)) {
                dump_snapshot(out_prefix, step, state, closureResult.outFields, params.n, has_type, has_r0);
            }

            if (step == nSteps) {
                manifest << "finalOccStd=" << shiftedResult.metrics.occStdAfter << "\n";
                manifest << "finalOutBand=" << shiftedResult.metrics.outBandAfter << "\n";
                manifest << "finalMeanKinetic=" << mean_kinetic(state.v, params.n) << "\n";
                manifest << "finalMeanVelocityX=" << mean_component(state.v, 0, params.n) << "\n";
                manifest << "finalMeanVelocityY=" << mean_component(state.v, 1, params.n) << "\n";
                manifest << "finalQx=" << flow_rate_qx(closureResult.outFields, params) << "\n";
                manifest << "finalBetaRepairOpt=" << closureResult.metrics.betaRepairOpt << "\n";
                manifest << "finalBetaRepairApplied=" << closureResult.metrics.betaRepairApplied << "\n";
                manifest << "finalBetaRepairNum=" << closureResult.metrics.betaRepairNum << "\n";
                manifest << "finalBetaRepairDen=" << closureResult.metrics.betaRepairDen << "\n";
                manifest << "finalRmsRepairDU=" << closureResult.metrics.rmsRepairDU << "\n";
                manifest << "finalMaxRepairDU=" << closureResult.metrics.maxRepairDU << "\n";
                manifest << "finalMeanAbsRepairDU=" << closureResult.metrics.meanAbsRepairDU << "\n";
                manifest << "finalMomentumDeltaX=" << closureResult.metrics.momentumDeltaX << "\n";
                manifest << "finalMomentumDeltaY=" << closureResult.metrics.momentumDeltaY << "\n";
                manifest << "totalParticlesMovedDense=" << (baseResult.metrics.nParticlesMovedDense + shiftedResult.metrics.nParticlesMovedDense) << "\n";
                manifest << "totalParticlesMovedSparse=" << (baseResult.metrics.nParticlesMovedSparse + shiftedResult.metrics.nParticlesMovedSparse) << "\n";
            }
        }

        return 0;
    } catch (const std::exception& e) {
        std::cerr << "Fatal error: " << e.what() << '\n';
        return 1;
    }
}
