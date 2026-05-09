
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
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
#include "visualization.h"
#include "zone_pass_openmp.h"

namespace {
using namespace mpcd;
using Clock = std::chrono::steady_clock;

struct PhaseTimers {
    double totalLoop = 0.0;
    double refBuild = 0.0;
    double base = 0.0;
    double shifted = 0.0;
    double closure = 0.0;
    double diagnostics = 0.0;
    double dumps = 0.0;

    double baseLayout = 0.0;
    double baseExtract = 0.0;
    double baseSnapshot = 0.0;
    double baseAlloc = 0.0;
    double baseKernel = 0.0;
    double basePack = 0.0;
    double baseMerge = 0.0;

    double shiftedLayout = 0.0;
    double shiftedExtract = 0.0;
    double shiftedSnapshot = 0.0;
    double shiftedAlloc = 0.0;
    double shiftedKernel = 0.0;
    double shiftedPack = 0.0;
    double shiftedMerge = 0.0;
};

double elapsed_seconds(const Clock::time_point& t0, const Clock::time_point& t1) {
    return std::chrono::duration<double>(t1 - t0).count();
}

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

std::pair<double,double> compute_occstd_outband(const CellFields& G, const Params& params) {
    std::vector<double> Nact;
    Nact.reserve(static_cast<std::size_t>(params.Nc));
    const double gamma = params.gamma;
    const double coef = params.coef;
    double highThr = (params.highMode == "1+coef") ? gamma * (1.0 + coef) : gamma + gamma * coef;
    double lowThr = (params.lowMode == "1+coef") ? gamma / (1.0 + coef) : gamma - gamma * coef;
    if (std::isfinite(params.lowThrBulkOverride)) lowThr = params.lowThrBulkOverride;
    int outBandCount = 0;
    int activeCount = 0;
    for (double n : G.N) {
        Nact.push_back(n);
        ++activeCount;
        if ((n > highThr) || (n > 0.0 && n < lowThr)) ++outBandCount;
    }
    double mean = 0.0;
    for (double n : Nact) mean += n;
    mean /= std::max(1, activeCount);
    double var = 0.0;
    for (double n : Nact) {
        double d = n - mean;
        var += d*d;
    }
    var /= std::max(1, activeCount);
    double occStd = std::sqrt(var) / std::max(gamma, 1e-12);
    double outBand = static_cast<double>(outBandCount) / std::max(1, activeCount);
    return {occStd, outBand};
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
        const Params params = read_params_kv(params_path);
        const auto kv = read_kv_map(params_path);
        const int nSteps = parse_int(require_key(kv, "benchmark_nSteps"));
        const int metricsEvery = parse_int(require_key(kv, "benchmark_metricsEvery"));
        const std::vector<int> dumpSteps = parse_steps_csv(require_key(kv, "benchmark_dumpSteps"));

        State state = read_state(x_path, v_path, type_path, r0_path, has_type, has_r0, params.n);
        const double rhoTarget = rho_target_scalar(params);
  Visualizer visualizer;
  visualizer.init(params);
  
        std::ofstream metrics(out_prefix + "_metrics.csv");
        if (!metrics) throw std::runtime_error("Cannot open metrics CSV for writing");
        metrics << "step,occStd,outBand,meanKinetic,meanUx,meanUy,Qx,baseOccStd,baseOutBand,shiftedOccStd,shiftedOutBand,meanPdrive,meanPdriveRaw,meanVelocityX,meanVelocityY,particlesMovedDense,particlesMovedSparse,betaRepairOpt,betaRepairApplied,betaRepairNum,betaRepairDen,rmsRepairDU,maxRepairDU,meanAbsRepairDU,nMaskedInterzoneCells,momentumDeltaX,momentumDeltaY,nThreadsUsedBase,nThreadsUsedShifted,timeStepTotal,timeRefBuild,timeBase,timeShifted,timeClosure,timeDiagnostics,timeDump\n";

        std::ofstream manifest(out_prefix + "_runout.kv");
        if (!manifest) throw std::runtime_error("Cannot open benchmark runout file");
        manifest << "inputTag=" << x_path << "\n";
        manifest << "outputTag=" << out_prefix << "\n";
        manifest << "benchmark_nSteps=" << nSteps << "\n";
        manifest << "benchmark_metricsEvery=" << metricsEvery << "\n";
        manifest << "benchmark_dumpSteps=" << require_key(kv, "benchmark_dumpSteps") << "\n";
        manifest << "nThreadsRequested=" << nthreads << "\n";

        PhaseTimers timers;
        const auto t_all_start = Clock::now();

        if (contains_step(dumpSteps, 0)) {
            const auto td0 = Clock::now();
            const CellFields G0 = compute_cell_fields(state.x, state.v, params, rhoTarget);
  if (visualizer.should_draw(0)) {
    visualizer.update(0, 0.0, params, state, G0);
  }
  
            dump_snapshot(out_prefix, 0, state, G0, params.n, has_type, has_r0);
            timers.dumps += elapsed_seconds(td0, Clock::now());
        }

        int finalThreadsBase = 1, finalThreadsShifted = 1;
        for (int step = 1; step <= nSteps; ++step) {
            const auto t_step_start = Clock::now();

            const auto t_ref0 = Clock::now();
            State stateRef = state;
            const std::vector<double> xBeforeStream = stateRef.x; for (int i = 0; i < params.n; ++i) {
                stateRef.v[2 * i] += params.bodyForceX * params.dt;
                stateRef.v[2 * i + 1] += params.g * params.dt;
                stateRef.x[2 * i] += params.dt * stateRef.v[2 * i];
                stateRef.x[2 * i + 1] += params.dt * stateRef.v[2 * i + 1];
            }
            WallInfo wallInfo;
            apply_cylinder_specular_swept_bc(stateRef.x, stateRef.v, xBeforeStream, params); apply_bc_general(stateRef.x, stateRef.v, params, wallInfo, 104729ULL + 10007ULL * static_cast<std::uint64_t>(step));
            const auto cid = srd_cell_id_with_random_shift(stateRef.x, params, 130363ULL + 10007ULL * static_cast<std::uint64_t>(step));
            srd_collision_step(stateRef.v, cid, params, 433494437ULL + 10007ULL * static_cast<std::uint64_t>(step));
            timers.refBuild += elapsed_seconds(t_ref0, Clock::now());

            const auto t_base0 = Clock::now();
            const auto baseResult = run_zone_pass_openmp(stateRef, params, "base", 88172645463325252ULL + 10007ULL * static_cast<std::uint64_t>(step), nthreads);
            timers.base += elapsed_seconds(t_base0, Clock::now());
            timers.baseLayout += baseResult.metrics.timeLayout;
            timers.baseExtract += baseResult.metrics.timeZoneExtract;
            timers.baseSnapshot += baseResult.metrics.timeSnapshot;
            timers.baseAlloc += baseResult.metrics.timeAlloc;
            timers.baseKernel += baseResult.metrics.timeKernel;
            timers.basePack += baseResult.metrics.timePack;
            timers.baseMerge += baseResult.metrics.timeMerge;

            const auto t_shift0 = Clock::now();
            const auto shiftedResult = run_zone_pass_openmp(baseResult.stateOut, params, "shifted", 88172645463325252ULL + 4099ULL + 10007ULL * static_cast<std::uint64_t>(step), nthreads);
            timers.shifted += elapsed_seconds(t_shift0, Clock::now());
            timers.shiftedLayout += shiftedResult.metrics.timeLayout;
            timers.shiftedExtract += shiftedResult.metrics.timeZoneExtract;
            timers.shiftedSnapshot += shiftedResult.metrics.timeSnapshot;
            timers.shiftedAlloc += shiftedResult.metrics.timeAlloc;
            timers.shiftedKernel += shiftedResult.metrics.timeKernel;
            timers.shiftedPack += shiftedResult.metrics.timePack;
            timers.shiftedMerge += shiftedResult.metrics.timeMerge;

            const auto t_closure0 = Clock::now();
            State shiftedStateForClosure = shiftedResult.stateOut;
      apply_cylinder_specular_position_bc(shiftedStateForClosure.x, shiftedStateForClosure.v, params);
      const auto closureResult = run_liquid_closure(stateRef, shiftedStateForClosure, params);
            const auto t_closure1 = Clock::now();
            state = closureResult.stateOut;
            
  if (visualizer.should_draw(step)) {
    visualizer.update(step, step * params.dt, params, state, closureResult.outFields);
    if (visualizer.should_close()) {
      break;
    }
  }            
            const double timeClosureStep = elapsed_seconds(t_closure0, t_closure1);
            timers.closure += timeClosureStep;

            finalThreadsBase = baseResult.metrics.nThreadsUsed;
            finalThreadsShifted = shiftedResult.metrics.nThreadsUsed;

            double baseOccStd = 0.0, baseOutBand = 0.0, shiftedOccStd = 0.0, shiftedOutBand = 0.0;

            if (metricsEvery > 0 && (step % metricsEvery == 0 || step == nSteps)) {
                const auto t_diag0 = Clock::now();
                const CellFields baseFields = compute_cell_fields(baseResult.stateOut.x, baseResult.stateOut.v, params, rhoTarget);
                const CellFields shiftedFields = compute_cell_fields(shiftedStateForClosure.x, shiftedStateForClosure.v, params, rhoTarget);
                const auto basePair = compute_occstd_outband(baseFields, params);
                const auto shiftedPair = compute_occstd_outband(shiftedFields, params);
                baseOccStd = basePair.first;
                baseOutBand = basePair.second;
                shiftedOccStd = shiftedPair.first;
                shiftedOutBand = shiftedPair.second;
                timers.diagnostics += elapsed_seconds(t_diag0, Clock::now());

                const double timeStepTotal = elapsed_seconds(t_step_start, Clock::now());
                metrics << step << ','
                        << shiftedOccStd << ','
                        << shiftedOutBand << ','
                        << mean_kinetic(state.v, params.n) << ','
                        << mean_field(closureResult.outFields.Ux) << ','
                        << mean_field(closureResult.outFields.Uy) << ','
                        << flow_rate_qx(closureResult.outFields, params) << ','
                        << baseOccStd << ','
                        << baseOutBand << ','
                        << shiftedOccStd << ','
                        << shiftedOutBand << ','
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
                        << closureResult.metrics.momentumDeltaY << ','
                        << baseResult.metrics.nThreadsUsed << ','
                        << shiftedResult.metrics.nThreadsUsed << ','
                        << timeStepTotal << ','
                        << elapsed_seconds(t_ref0, t_base0) << ','
                        << elapsed_seconds(t_base0, t_shift0) << ','
                        << elapsed_seconds(t_shift0, t_closure0) << ','
                        << timeClosureStep << ','
                        << elapsed_seconds(t_diag0, Clock::now()) << ','
                        << 0.0 << '\n';
            }

            if (contains_step(dumpSteps, step)) {
                const auto t_dump0 = Clock::now();
                dump_snapshot(out_prefix, step, state, closureResult.outFields, params.n, has_type, has_r0);
                timers.dumps += elapsed_seconds(t_dump0, Clock::now());
            }

            timers.totalLoop += elapsed_seconds(t_step_start, Clock::now());

            if (step == nSteps) {
                if (!(metricsEvery > 0 && (step % metricsEvery == 0 || step == nSteps))) {
                    const CellFields baseFields = compute_cell_fields(baseResult.stateOut.x, baseResult.stateOut.v, params, rhoTarget);
                    const CellFields shiftedFields = compute_cell_fields(shiftedStateForClosure.x, shiftedStateForClosure.v, params, rhoTarget);
                    const auto basePair = compute_occstd_outband(baseFields, params);
                    const auto shiftedPair = compute_occstd_outband(shiftedFields, params);
                    baseOccStd = basePair.first;
                    baseOutBand = basePair.second;
                    shiftedOccStd = shiftedPair.first;
                    shiftedOutBand = shiftedPair.second;
                }
                manifest << "finalOccStd=" << shiftedOccStd << "\n";
                manifest << "finalOutBand=" << shiftedOutBand << "\n";
                manifest << "finalMeanKinetic=" << mean_kinetic(state.v, params.n) << "\n";
                manifest << "finalMeanVelocityX=" << mean_component(state.v, 0, params.n) << "\n";
                manifest << "finalMeanVelocityY=" << mean_component(state.v, 1, params.n) << "\n";
                manifest << "finalQx=" << flow_rate_qx(closureResult.outFields, params) << "\n";
                manifest << "totalParticlesMovedDense=" << (baseResult.metrics.nParticlesMovedDense + shiftedResult.metrics.nParticlesMovedDense) << "\n";
                manifest << "totalParticlesMovedSparse=" << (baseResult.metrics.nParticlesMovedSparse + shiftedResult.metrics.nParticlesMovedSparse) << "\n";
                manifest << "finalBetaRepairOpt=" << closureResult.metrics.betaRepairOpt << "\n";
                manifest << "finalBetaRepairApplied=" << closureResult.metrics.betaRepairApplied << "\n";
                manifest << "finalBetaRepairNum=" << closureResult.metrics.betaRepairNum << "\n";
                manifest << "finalBetaRepairDen=" << closureResult.metrics.betaRepairDen << "\n";
                manifest << "finalRmsRepairDU=" << closureResult.metrics.rmsRepairDU << "\n";
                manifest << "finalMaxRepairDU=" << closureResult.metrics.maxRepairDU << "\n";
                manifest << "finalMeanAbsRepairDU=" << closureResult.metrics.meanAbsRepairDU << "\n";
                manifest << "finalMomentumDeltaX=" << closureResult.metrics.momentumDeltaX << "\n";
                manifest << "finalMomentumDeltaY=" << closureResult.metrics.momentumDeltaY << "\n";
                manifest << "nThreadsUsedBase=" << finalThreadsBase << "\n";
                manifest << "nThreadsUsedShifted=" << finalThreadsShifted << "\n";
            }
        }

        const double totalWall = elapsed_seconds(t_all_start, Clock::now());
        manifest << "timeTotalWall=" << totalWall << "\n";
        manifest << "timeLoopTotal=" << timers.totalLoop << "\n";
        manifest << "timeRefBuild=" << timers.refBuild << "\n";
        manifest << "timeBase=" << timers.base << "\n";
        manifest << "timeShifted=" << timers.shifted << "\n";
        manifest << "timeClosure=" << timers.closure << "\n";
        manifest << "timeDiagnostics=" << timers.diagnostics << "\n";
        manifest << "timeDumps=" << timers.dumps << "\n";
        manifest << "timePerStepMean=" << (timers.totalLoop / std::max(1, nSteps)) << "\n";
        manifest << "fracRefBuild=" << (timers.totalLoop > 0 ? timers.refBuild / timers.totalLoop : 0.0) << "\n";
        manifest << "fracBase=" << (timers.totalLoop > 0 ? timers.base / timers.totalLoop : 0.0) << "\n";
        manifest << "fracShifted=" << (timers.totalLoop > 0 ? timers.shifted / timers.totalLoop : 0.0) << "\n";
        manifest << "fracClosure=" << (timers.totalLoop > 0 ? timers.closure / timers.totalLoop : 0.0) << "\n";
        manifest << "fracDiagnostics=" << (timers.totalLoop > 0 ? timers.diagnostics / timers.totalLoop : 0.0) << "\n";
        manifest << "fracDumps=" << (timers.totalLoop > 0 ? timers.dumps / timers.totalLoop : 0.0) << "\n";
        manifest << "timeBaseLayout=" << timers.baseLayout << "\n";
        manifest << "timeBaseExtract=" << timers.baseExtract << "\n";
        manifest << "timeBaseSnapshot=" << timers.baseSnapshot << "\n";
        manifest << "timeBaseAlloc=" << timers.baseAlloc << "\n";
        manifest << "timeBaseKernel=" << timers.baseKernel << "\n";
        manifest << "timeBasePack=" << timers.basePack << "\n";
        manifest << "timeBaseMerge=" << timers.baseMerge << "\n";
        manifest << "timeShiftedLayout=" << timers.shiftedLayout << "\n";
        manifest << "timeShiftedExtract=" << timers.shiftedExtract << "\n";
        manifest << "timeShiftedSnapshot=" << timers.shiftedSnapshot << "\n";
        manifest << "timeShiftedAlloc=" << timers.shiftedAlloc << "\n";
        manifest << "timeShiftedKernel=" << timers.shiftedKernel << "\n";
        manifest << "timeShiftedPack=" << timers.shiftedPack << "\n";
        manifest << "timeShiftedMerge=" << timers.shiftedMerge << "\n";
        manifest << "fracBaseLayout=" << (timers.base > 0 ? timers.baseLayout / timers.base : 0.0) << "\n";
        manifest << "fracBaseExtract=" << (timers.base > 0 ? timers.baseExtract / timers.base : 0.0) << "\n";
        manifest << "fracBaseSnapshot=" << (timers.base > 0 ? timers.baseSnapshot / timers.base : 0.0) << "\n";
        manifest << "fracBaseAlloc=" << (timers.base > 0 ? timers.baseAlloc / timers.base : 0.0) << "\n";
        manifest << "fracBaseKernel=" << (timers.base > 0 ? timers.baseKernel / timers.base : 0.0) << "\n";
        manifest << "fracBasePack=" << (timers.base > 0 ? timers.basePack / timers.base : 0.0) << "\n";
        manifest << "fracBaseMerge=" << (timers.base > 0 ? timers.baseMerge / timers.base : 0.0) << "\n";
        manifest << "fracShiftedLayout=" << (timers.shifted > 0 ? timers.shiftedLayout / timers.shifted : 0.0) << "\n";
        manifest << "fracShiftedExtract=" << (timers.shifted > 0 ? timers.shiftedExtract / timers.shifted : 0.0) << "\n";
        manifest << "fracShiftedSnapshot=" << (timers.shifted > 0 ? timers.shiftedSnapshot / timers.shifted : 0.0) << "\n";
        manifest << "fracShiftedAlloc=" << (timers.shifted > 0 ? timers.shiftedAlloc / timers.shifted : 0.0) << "\n";
        manifest << "fracShiftedKernel=" << (timers.shifted > 0 ? timers.shiftedKernel / timers.shifted : 0.0) << "\n";
        manifest << "fracShiftedPack=" << (timers.shifted > 0 ? timers.shiftedPack / timers.shifted : 0.0) << "\n";
        manifest << "fracShiftedMerge=" << (timers.shifted > 0 ? timers.shiftedMerge / timers.shifted : 0.0) << "\n";
    visualizer.shutdown();
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "Fatal error: " << e.what() << '\n';
        return 1;
    }
}
