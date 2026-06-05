#include "cuda_resampling_guard.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <random>
#include <sstream>
#include <string>
#include <vector>

namespace {

struct CaseSpec {
    int nx = 64;
    int ny = 64;
    int gamma = 20;
    bool activeMask = true;
};

std::vector<CaseSpec> parse_cases(const char* env) {
    std::vector<CaseSpec> out;
    std::string s = env && *env ? env : "64:64:20 128:128:20";
    std::istringstream iss(s);
    std::string tok;
    while (iss >> tok) {
        std::replace(tok.begin(), tok.end(), 'x', ':');
        std::vector<int> vals;
        std::stringstream ss(tok);
        std::string part;
        while (std::getline(ss, part, ':')) {
            if (!part.empty()) vals.push_back(std::stoi(part));
        }
        if (vals.size() >= 3) out.push_back({vals[0], vals[1], vals[2], true});
    }
    if (out.empty()) out.push_back({64,64,20,true});
    return out;
}

void cpu_classify(
    const std::vector<std::uint32_t>& count,
    const std::vector<double>& mass,
    const std::vector<std::uint8_t>& active,
    const mpcd::CudaResamplingGuardParams& params,
    std::vector<std::uint8_t>& wet,
    std::vector<std::uint8_t>& dry,
    std::vector<std::uint8_t>& poor,
    std::vector<std::uint8_t>& rich,
    std::vector<std::uint8_t>& target)
{
    const std::size_t n = count.size();
    wet.assign(n, 0u); dry.assign(n, 0u); poor.assign(n, 0u); rich.assign(n, 0u); target.assign(n, 0u);
    const double poorLimit = params.targetCellMass * (1.0 - params.poorRelativeThreshold);
    const double richLimit = params.targetCellMass * (1.0 + params.richRelativeThreshold);
    for (std::size_t c = 0; c < n; ++c) {
        const bool isActive = (!params.useActiveMask) || active[c] != 0u;
        const bool isWet = isActive && count[c] > 0u;
        const bool isDry = isActive && count[c] == 0u;
        const bool isPoor = isActive && (count[c] < params.minFluidCount || mass[c] < poorLimit);
        const bool isRich = isActive && (mass[c] > richLimit);
        const bool isTarget = isActive && isWet && !isPoor && !isRich;
        wet[c] = static_cast<std::uint8_t>(isWet ? 1u : 0u);
        dry[c] = static_cast<std::uint8_t>(isDry ? 1u : 0u);
        poor[c] = static_cast<std::uint8_t>(isPoor ? 1u : 0u);
        rich[c] = static_cast<std::uint8_t>(isRich ? 1u : 0u);
        target[c] = static_cast<std::uint8_t>(isTarget ? 1u : 0u);
    }
}

std::uint64_t mismatches(const std::vector<std::uint8_t>& a, const std::vector<std::uint8_t>& b) {
    std::uint64_t m = 0u;
    for (std::size_t i = 0; i < a.size(); ++i) if (a[i] != b[i]) ++m;
    return m;
}

} // namespace

int main() {
    const auto cases = parse_cases(std::getenv("GRID_CASES"));
    const std::string outPath = std::getenv("OUT_CSV") ? std::getenv("OUT_CSV") :
        "dev_history/artifacts/gpu_cuda_resampling_0227/cuda_resampling_guard_smoke_0227.csv";
    std::ofstream csv(outPath);
    csv << "case,Nx,Ny,gamma,cells,activeCells,wetCells,dryCells,poorCells,richCells,targetBandCells,"
           "wetMismatches,dryMismatches,poorMismatches,richMismatches,targetMismatches,verdict\n";

    bool allPass = true;
    for (const CaseSpec& cs : cases) {
        const int nc = cs.nx * cs.ny;
        const double targetMass = static_cast<double>(std::max(1, cs.gamma));
        std::vector<std::uint32_t> count(static_cast<std::size_t>(nc));
        std::vector<double> mass(static_cast<std::size_t>(nc));
        std::vector<std::uint8_t> active(static_cast<std::size_t>(nc), 1u);

        std::mt19937_64 rng(0x9e3779b97f4a7c15ULL ^ (static_cast<std::uint64_t>(cs.nx) << 32) ^ cs.ny);
        std::normal_distribution<double> massNoise(0.0, 0.18 * targetMass);
        for (int iy = 0; iy < cs.ny; ++iy) {
            for (int ix = 0; ix < cs.nx; ++ix) {
                const int c = ix + iy * cs.nx;
                const bool inactive = (ix < 2 || iy < 1 || ((ix + 3 * iy) % 97 == 0));
                active[c] = cs.activeMask && inactive ? 0u : 1u;
                double m = std::max(0.0, targetMass + massNoise(rng));
                if ((ix + iy) % 31 == 0) m *= 0.45;      // poor pocket
                if ((2 * ix + iy) % 43 == 0) m *= 1.75;  // rich pocket
                if (active[c] == 0u) m = 0.0;
                mass[c] = m;
                count[c] = active[c] ? static_cast<std::uint32_t>(std::max(0, static_cast<int>(std::llround(m)))) : 0u;
            }
        }

        mpcd::CudaResamplingGuardParams params;
        params.targetCellMass = targetMass;
        params.poorRelativeThreshold = 0.12;
        params.richRelativeThreshold = 0.12;
        params.minFluidCount = 2u;
        params.useActiveMask = cs.activeMask;

        std::vector<std::uint8_t> cpuWet, cpuDry, cpuPoor, cpuRich, cpuTarget;
        std::vector<std::uint8_t> gpuWet, gpuDry, gpuPoor, gpuRich, gpuTarget;
        cpu_classify(count, mass, active, params, cpuWet, cpuDry, cpuPoor, cpuRich, cpuTarget);

        mpcd::CudaResamplingGuardDiagnostics diag;
        mpcd::cuda_resampling_classify_cells_0227(count, mass, active, params,
            gpuWet, gpuDry, gpuPoor, gpuRich, gpuTarget, &diag);

        const auto mw = mismatches(cpuWet, gpuWet);
        const auto md = mismatches(cpuDry, gpuDry);
        const auto mp = mismatches(cpuPoor, gpuPoor);
        const auto mr = mismatches(cpuRich, gpuRich);
        const auto mt = mismatches(cpuTarget, gpuTarget);
        const bool pass = (mw + md + mp + mr + mt) == 0u;
        allPass = allPass && pass;

        const std::string label = std::to_string(cs.nx) + "x" + std::to_string(cs.ny) + "_g" + std::to_string(cs.gamma);
        csv << label << ',' << cs.nx << ',' << cs.ny << ',' << cs.gamma << ',' << nc << ','
            << diag.activeCells << ',' << diag.wetCells << ',' << diag.dryCells << ','
            << diag.poorCells << ',' << diag.richCells << ',' << diag.targetBandCells << ','
            << mw << ',' << md << ',' << mp << ',' << mr << ',' << mt << ','
            << (pass ? "PASS" : "FAIL") << '\n';
        std::cout << "[0227-resampling-guard] " << (pass ? "PASS " : "FAIL ") << label
                  << " cells=" << nc << " active=" << diag.activeCells
                  << " poor=" << diag.poorCells << " rich=" << diag.richCells
                  << " mismatches=" << (mw + md + mp + mr + mt) << "\n";
    }
    std::cout << "[0227-resampling-guard] wrote " << outPath << "\n";
    return allPass ? 0 : 1;
}
