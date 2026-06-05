#include "cuda_resampling_guard.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
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

struct CpuPlan {
    std::vector<std::uint32_t> poorCells;
    std::vector<std::uint32_t> richCells;
    std::vector<double> deficits;
    std::vector<double> excesses;
    std::vector<std::uint32_t> receivers;
    std::vector<std::uint32_t> donors;
    std::vector<double> transferMass;
    double totalDeficit = 0.0;
    double totalExcess = 0.0;
    double plannedMass = 0.0;
};

struct Pair { std::uint32_t cell; double amount; };

void sort_pairs(std::vector<std::uint32_t>& cells, std::vector<double>& amounts) {
    std::vector<Pair> pairs;
    pairs.reserve(cells.size());
    for (std::size_t i = 0; i < cells.size(); ++i) pairs.push_back({cells[i], amounts[i]});
    std::sort(pairs.begin(), pairs.end(), [](const Pair& a, const Pair& b) { return a.cell < b.cell; });
    for (std::size_t i = 0; i < pairs.size(); ++i) { cells[i] = pairs[i].cell; amounts[i] = pairs[i].amount; }
}

CpuPlan cpu_compact_and_plan(
    const std::vector<std::uint32_t>& count,
    const std::vector<double>& mass,
    const std::vector<std::uint8_t>& active,
    const mpcd::CudaResamplingPlanParams& params)
{
    CpuPlan out;
    const double target = params.guard.targetCellMass;
    const double poorLimit = target * (1.0 - params.guard.poorRelativeThreshold);
    const double richLimit = target * (1.0 + params.guard.richRelativeThreshold);
    for (std::size_t c = 0; c < count.size(); ++c) {
        const bool isActive = (!params.guard.useActiveMask) || active[c] != 0u;
        if (!isActive) continue;
        const bool isPoor = (count[c] < params.guard.minFluidCount || mass[c] < poorLimit);
        const bool isRich = (mass[c] > richLimit);
        if (isPoor) {
            out.poorCells.push_back(static_cast<std::uint32_t>(c));
            out.deficits.push_back(std::max(0.0, target - mass[c]));
        }
        if (isRich) {
            out.richCells.push_back(static_cast<std::uint32_t>(c));
            out.excesses.push_back(std::max(0.0, mass[c] - target));
        }
    }
    sort_pairs(out.poorCells, out.deficits);
    sort_pairs(out.richCells, out.excesses);
    for (double d : out.deficits) out.totalDeficit += d;
    for (double e : out.excesses) out.totalExcess += e;

    std::size_t ip = 0u;
    std::size_t ir = 0u;
    double dp = out.deficits.empty() ? 0.0 : out.deficits[0];
    double er = out.excesses.empty() ? 0.0 : out.excesses[0];
    const std::size_t maxT = params.maxTransfers == 0u ? std::numeric_limits<std::size_t>::max() : params.maxTransfers;
    while (ip < out.poorCells.size() && ir < out.richCells.size() && out.receivers.size() < maxT) {
        while (ip < out.poorCells.size() && dp <= params.minTransferMass) {
            ++ip;
            if (ip < out.poorCells.size()) dp = out.deficits[ip];
        }
        while (ir < out.richCells.size() && er <= params.minTransferMass) {
            ++ir;
            if (ir < out.richCells.size()) er = out.excesses[ir];
        }
        if (ip >= out.poorCells.size() || ir >= out.richCells.size()) break;
        const double m = std::min(dp, er);
        if (m > params.minTransferMass) {
            out.receivers.push_back(out.poorCells[ip]);
            out.donors.push_back(out.richCells[ir]);
            out.transferMass.push_back(m);
            out.plannedMass += m;
        }
        dp -= m;
        er -= m;
    }
    return out;
}

std::uint64_t mismatch_u32(const std::vector<std::uint32_t>& a, const std::vector<std::uint32_t>& b) {
    if (a.size() != b.size()) return static_cast<std::uint64_t>(std::max(a.size(), b.size()));
    std::uint64_t n = 0u;
    for (std::size_t i = 0; i < a.size(); ++i) if (a[i] != b[i]) ++n;
    return n;
}

double max_abs_diff(const std::vector<double>& a, const std::vector<double>& b) {
    if (a.size() != b.size()) return std::numeric_limits<double>::infinity();
    double m = 0.0;
    for (std::size_t i = 0; i < a.size(); ++i) m = std::max(m, std::abs(a[i] - b[i]));
    return m;
}

double sum_vec(const std::vector<double>& x) {
    double s = 0.0;
    for (double v : x) s += v;
    return s;
}

} // namespace

int main() {
    const auto cases = parse_cases(std::getenv("GRID_CASES"));
    const std::string outPath = std::getenv("OUT_CSV") ? std::getenv("OUT_CSV") :
        "dev_history/artifacts/gpu_cuda_resampling_0228/cuda_resampling_plan_smoke_0228.csv";
    std::ofstream csv(outPath);
    csv << std::setprecision(17);
    csv << "case,Nx,Ny,gamma,cells,activeCells,poorCells,richCells,transfers,totalDeficit,totalExcess,plannedMass,"
           "poorIndexMismatches,richIndexMismatches,deficitMaxAbs,excessMaxAbs,receiverMismatches,donorMismatches,transferMassMaxAbs,"
           "diagTotalDeficitDiff,diagTotalExcessDiff,diagPlannedMassDiff,verdict\n";

    bool allPass = true;
    for (const CaseSpec& cs : cases) {
        const int nc = cs.nx * cs.ny;
        const double targetMass = static_cast<double>(std::max(1, cs.gamma));
        std::vector<std::uint32_t> count(static_cast<std::size_t>(nc));
        std::vector<double> mass(static_cast<std::size_t>(nc));
        std::vector<std::uint8_t> active(static_cast<std::size_t>(nc), 1u);

        std::mt19937_64 rng(0xf00dd00d12345678ULL ^ (static_cast<std::uint64_t>(cs.nx) << 32) ^ cs.ny);
        std::normal_distribution<double> massNoise(0.0, 0.22 * targetMass);
        for (int iy = 0; iy < cs.ny; ++iy) {
            for (int ix = 0; ix < cs.nx; ++ix) {
                const int c = ix + iy * cs.nx;
                const bool inactive = (ix < 2 || iy < 1 || ((ix + 3 * iy) % 97 == 0));
                active[c] = cs.activeMask && inactive ? 0u : 1u;
                double m = std::max(0.0, targetMass + massNoise(rng));
                if ((ix + iy) % 31 == 0) m *= 0.42;       // receiver pocket
                if ((2 * ix + iy) % 43 == 0) m *= 1.85;   // donor pocket
                if ((ix + 5 * iy) % 211 == 0) m = 0.0;    // dry/void pocket
                if (active[c] == 0u) m = 0.0;
                mass[c] = m;
                count[c] = active[c] ? static_cast<std::uint32_t>(std::max(0, static_cast<int>(std::llround(m)))) : 0u;
            }
        }

        mpcd::CudaResamplingPlanParams params;
        params.guard.targetCellMass = targetMass;
        params.guard.poorRelativeThreshold = 0.12;
        params.guard.richRelativeThreshold = 0.12;
        params.guard.minFluidCount = 2u;
        params.guard.useActiveMask = cs.activeMask;
        params.minTransferMass = 1.0e-12;
        params.maxTransfers = 0u;

        const CpuPlan cpu = cpu_compact_and_plan(count, mass, active, params);

        std::vector<std::uint32_t> gpuPoor, gpuRich, gpuReceivers, gpuDonors;
        std::vector<double> gpuDef, gpuExc, gpuMass;
        mpcd::CudaResamplingPlanDiagnostics diag;
        mpcd::cuda_resampling_compact_and_plan_0228(
            count, mass, active, params,
            gpuPoor, gpuRich, gpuDef, gpuExc,
            gpuReceivers, gpuDonors, gpuMass, &diag);

        const std::uint64_t poorMis = mismatch_u32(cpu.poorCells, gpuPoor);
        const std::uint64_t richMis = mismatch_u32(cpu.richCells, gpuRich);
        const std::uint64_t recMis = mismatch_u32(cpu.receivers, gpuReceivers);
        const std::uint64_t donorMis = mismatch_u32(cpu.donors, gpuDonors);
        const double defDiff = max_abs_diff(cpu.deficits, gpuDef);
        const double excDiff = max_abs_diff(cpu.excesses, gpuExc);
        const double massDiff = max_abs_diff(cpu.transferMass, gpuMass);
        const double diagDefDiff = std::abs(diag.totalDeficit - cpu.totalDeficit);
        const double diagExcDiff = std::abs(diag.totalExcess - cpu.totalExcess);
        const double diagPlanDiff = std::abs(diag.plannedMass - cpu.plannedMass);

        const bool pass = poorMis == 0u && richMis == 0u && recMis == 0u && donorMis == 0u &&
                          defDiff <= 1e-12 && excDiff <= 1e-12 && massDiff <= 1e-12 &&
                          diagDefDiff <= 1e-10 && diagExcDiff <= 1e-10 && diagPlanDiff <= 1e-10;
        allPass = allPass && pass;

        const std::string label = std::to_string(cs.nx) + "x" + std::to_string(cs.ny) + "_g" + std::to_string(cs.gamma);
        csv << label << ',' << cs.nx << ',' << cs.ny << ',' << cs.gamma << ',' << nc << ','
            << diag.activeCells << ',' << diag.poorCells << ',' << diag.richCells << ',' << diag.transfers << ','
            << diag.totalDeficit << ',' << diag.totalExcess << ',' << diag.plannedMass << ','
            << poorMis << ',' << richMis << ',' << defDiff << ',' << excDiff << ','
            << recMis << ',' << donorMis << ',' << massDiff << ','
            << diagDefDiff << ',' << diagExcDiff << ',' << diagPlanDiff << ','
            << (pass ? "PASS" : "FAIL") << '\n';

        std::cout << "[0228-resampling-plan] " << (pass ? "PASS " : "FAIL ") << label
                  << " cells=" << nc
                  << " active=" << diag.activeCells
                  << " poor=" << diag.poorCells
                  << " rich=" << diag.richCells
                  << " transfers=" << diag.transfers
                  << " plannedMass=" << diag.plannedMass
                  << " mismatches=" << (poorMis + richMis + recMis + donorMis) << "\n";
    }

    std::cout << "[0228-resampling-plan] wrote " << outPath << "\n";
    return allPass ? 0 : 1;
}
