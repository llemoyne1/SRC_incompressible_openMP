#include "cuda_resampling_guard.h"
#include "cuda_resampling_particle_ops.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <numeric>
#include <random>
#include <sstream>
#include <string>
#include <vector>

namespace {

struct CaseSpec { int nx = 64; int ny = 64; int gamma = 20; bool activeMask = true; };

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
        while (std::getline(ss, part, ':')) if (!part.empty()) vals.push_back(std::stoi(part));
        if (vals.size() >= 3) out.push_back({vals[0], vals[1], vals[2], true});
    }
    if (out.empty()) out.push_back({64,64,20,true});
    return out;
}

struct SyntheticParticles {
    std::vector<std::uint32_t> count;
    std::vector<double> cellMass;
    std::vector<std::uint8_t> active;
    std::vector<std::uint32_t> particleCell;
    std::vector<std::uint8_t> particleRole;
    std::vector<double> particleMass;
};

SyntheticParticles make_case(const CaseSpec& cs) {
    const int nc = cs.nx * cs.ny;
    const double targetMass = static_cast<double>(std::max(1, cs.gamma));
    SyntheticParticles st;
    st.count.resize(static_cast<std::size_t>(nc));
    st.cellMass.resize(static_cast<std::size_t>(nc));
    st.active.assign(static_cast<std::size_t>(nc), 1u);

    std::mt19937_64 rng(0x0232c0ffeeULL ^ (static_cast<std::uint64_t>(cs.nx) << 32) ^ static_cast<std::uint64_t>(cs.ny));
    std::normal_distribution<double> massNoise(0.0, 0.25 * targetMass);
    for (int iy = 0; iy < cs.ny; ++iy) {
        for (int ix = 0; ix < cs.nx; ++ix) {
            const int c = ix + iy * cs.nx;
            const bool inactive = (ix < 2 || iy < 1 || ((ix + 7 * iy) % 131 == 0));
            st.active[c] = cs.activeMask && inactive ? 0u : 1u;
            double m = std::max(0.0, targetMass + massNoise(rng));
            if ((ix + 2 * iy) % 29 == 0) m *= 0.35;       // receiver pocket
            if ((3 * ix + iy) % 37 == 0) m *= 1.95;       // donor pocket
            if ((ix + 5 * iy) % 223 == 0) m = 0.0;        // dry/void pocket
            if (st.active[c] == 0u) m = 0.0;
            st.cellMass[c] = m;
            st.count[c] = st.active[c] ? static_cast<std::uint32_t>(std::max(0, static_cast<int>(std::llround(m)))) : 0u;
            if (st.active[c] && m > 0.0 && st.count[c] == 0u) st.count[c] = 1u;
        }
    }

    std::uint64_t totalParticles = 0u;
    for (std::uint32_t n : st.count) totalParticles += n;
    st.particleCell.reserve(static_cast<std::size_t>(totalParticles));
    st.particleRole.reserve(static_cast<std::size_t>(totalParticles));
    st.particleMass.reserve(static_cast<std::size_t>(totalParticles));

    for (std::uint32_t c = 0; c < static_cast<std::uint32_t>(nc); ++c) {
        const std::uint32_t n = st.count[c];
        if (n == 0u) continue;
        const double mp = st.cellMass[c] / static_cast<double>(n);
        for (std::uint32_t j = 0; j < n; ++j) {
            st.particleCell.push_back(c);
            // First particle in every occupied cell is fluid so every rich donor is feasible.
            // Additional mixed roles stress the selection mask without making donor cells empty.
            const bool latent = (j > 0u) && (((c + 17u * j) % 19u) == 0u);
            st.particleRole.push_back(static_cast<std::uint8_t>(latent ? 1u : 0u));
            st.particleMass.push_back(mp * (1.0 + 0.03 * static_cast<double>(static_cast<int>(j % 5u) - 2)));
        }
    }
    return st;
}

void cpu_select(
    const std::vector<std::uint32_t>& particleCell,
    const std::vector<std::uint8_t>& particleRole,
    const std::vector<double>& particleMass,
    std::uint32_t nCells,
    const std::vector<std::uint32_t>& donorCell,
    std::uint8_t fluidRole,
    std::uint32_t invalidParticle,
    std::vector<std::uint32_t>& selected,
    std::vector<double>& selectedMass,
    std::vector<std::uint32_t>& eligibleCount)
{
    std::vector<std::uint32_t> first(nCells, invalidParticle);
    eligibleCount.assign(nCells, 0u);
    for (std::uint32_t i = 0; i < particleCell.size(); ++i) {
        if (particleRole[i] != fluidRole) continue;
        const std::uint32_t c = particleCell[i];
        if (c >= nCells) continue;
        eligibleCount[c] += 1u;
        if (i < first[c]) first[c] = i;
    }
    selected.resize(donorCell.size());
    selectedMass.resize(donorCell.size());
    for (std::size_t t = 0; t < donorCell.size(); ++t) {
        const std::uint32_t c = donorCell[t];
        const std::uint32_t p = c < nCells ? first[c] : invalidParticle;
        selected[t] = p;
        selectedMass[t] = p == invalidParticle ? 0.0 : particleMass[p];
    }
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

} // namespace

int main() {
    const auto cases = parse_cases(std::getenv("GRID_CASES"));
    const std::string outPath = std::getenv("OUT_CSV") ? std::getenv("OUT_CSV") :
        "dev_history/artifacts/gpu_cuda_resampling_0232/cuda_resampling_particle_select_smoke_0232.csv";
    std::ofstream csv(outPath);
    csv << std::setprecision(17);
    csv << "case,Nx,Ny,gamma,cells,particles,poorCells,richCells,transfers,totalTransferMass,selectedTransfers,missingDonorParticleTransfers,"
           "selectedMismatches,selectedMassMaxAbs,eligibleCountMismatches,uploadSeconds,kernelSeconds,downloadSeconds,totalSeconds,verdict\n";

    bool allPass = true;
    for (const CaseSpec& cs : cases) {
        const int nc = cs.nx * cs.ny;
        const double targetMass = static_cast<double>(std::max(1, cs.gamma));
        SyntheticParticles st = make_case(cs);

        mpcd::CudaResamplingPlanParams planParams;
        planParams.guard.targetCellMass = targetMass;
        planParams.guard.poorRelativeThreshold = 0.12;
        planParams.guard.richRelativeThreshold = 0.12;
        planParams.guard.minFluidCount = 2u;
        planParams.guard.useActiveMask = true;
        planParams.minTransferMass = 1.0e-12;
        planParams.maxTransfers = 0u;

        std::vector<std::uint32_t> poor, rich, receiver, donor;
        std::vector<double> deficit, excess, transferMass;
        mpcd::CudaResamplingPlanDiagnostics planDiag;
        mpcd::cuda_resampling_compact_and_plan_0228(
            st.count, st.cellMass, st.active, planParams,
            poor, rich, deficit, excess, receiver, donor, transferMass, &planDiag);

        mpcd::CudaResamplingParticleSelectParams selectParams;
        std::vector<std::uint32_t> cpuSelected, gpuSelected, cpuEligible, gpuEligible;
        std::vector<double> cpuSelectedMass, gpuSelectedMass;
        cpu_select(st.particleCell, st.particleRole, st.particleMass,
                   static_cast<std::uint32_t>(nc), donor, selectParams.fluidRole,
                   selectParams.invalidParticle, cpuSelected, cpuSelectedMass, cpuEligible);

        mpcd::CudaResamplingParticleSelectDiagnostics diag;
        mpcd::cuda_resampling_select_donor_particles_0232(
            st.particleCell, st.particleRole, st.particleMass,
            static_cast<std::uint32_t>(nc), donor, transferMass, selectParams,
            gpuSelected, gpuSelectedMass, &gpuEligible, &diag);

        const std::uint64_t selectedMis = mismatch_u32(cpuSelected, gpuSelected);
        const double selectedMassDiff = max_abs_diff(cpuSelectedMass, gpuSelectedMass);
        const std::uint64_t eligibleMis = mismatch_u32(cpuEligible, gpuEligible);
        const bool pass = selectedMis == 0u && selectedMassDiff <= 1e-12 && eligibleMis == 0u &&
                          diag.missingDonorParticleTransfers == 0u && diag.selectedTransfers == donor.size();
        allPass = allPass && pass;
        const std::string label = std::to_string(cs.nx) + "x" + std::to_string(cs.ny) + "_g" + std::to_string(cs.gamma);
        csv << label << ',' << cs.nx << ',' << cs.ny << ',' << cs.gamma << ',' << nc << ','
            << st.particleCell.size() << ',' << planDiag.poorCells << ',' << planDiag.richCells << ',' << planDiag.transfers << ','
            << diag.totalTransferMass << ',' << diag.selectedTransfers << ',' << diag.missingDonorParticleTransfers << ','
            << selectedMis << ',' << selectedMassDiff << ',' << eligibleMis << ','
            << diag.uploadSeconds << ',' << diag.kernelSeconds << ',' << diag.downloadSeconds << ',' << diag.totalSeconds << ','
            << (pass ? "PASS" : "FAIL") << '\n';

        std::cout << "[0232-resampling-particle-select] " << (pass ? "PASS " : "FAIL ") << label
                  << " cells=" << nc
                  << " particles=" << st.particleCell.size()
                  << " transfers=" << planDiag.transfers
                  << " selected=" << diag.selectedTransfers
                  << " missing=" << diag.missingDonorParticleTransfers
                  << " mismatches=" << (selectedMis + eligibleMis)
                  << "\n";
    }
    std::cout << "[0232-resampling-particle-select] wrote " << outPath << "\n";
    return allPass ? 0 : 1;
}
