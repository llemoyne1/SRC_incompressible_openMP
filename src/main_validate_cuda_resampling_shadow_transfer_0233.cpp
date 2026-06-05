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
#include <unordered_set>
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
    std::vector<double> particleVx;
    std::vector<double> particleVy;
};

SyntheticParticles make_case(const CaseSpec& cs) {
    const int nc = cs.nx * cs.ny;
    const double targetMass = static_cast<double>(std::max(1, cs.gamma));
    SyntheticParticles st;
    st.count.resize(static_cast<std::size_t>(nc));
    st.cellMass.resize(static_cast<std::size_t>(nc));
    st.active.assign(static_cast<std::size_t>(nc), 1u);

    std::mt19937_64 rng(0x0233faceULL ^ (static_cast<std::uint64_t>(cs.nx) << 32) ^ static_cast<std::uint64_t>(cs.ny));
    std::normal_distribution<double> massNoise(0.0, 0.24 * targetMass);
    for (int iy = 0; iy < cs.ny; ++iy) {
        for (int ix = 0; ix < cs.nx; ++ix) {
            const int c = ix + iy * cs.nx;
            const bool inactive = (ix < 2 || iy < 1 || ((ix + 7 * iy) % 131 == 0));
            st.active[c] = cs.activeMask && inactive ? 0u : 1u;
            double m = std::max(0.0, targetMass + massNoise(rng));
            if ((ix + 2 * iy) % 29 == 0) m *= 0.35;
            if ((3 * ix + iy) % 37 == 0) m *= 1.95;
            if ((ix + 5 * iy) % 223 == 0) m = 0.0;
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
    st.particleVx.reserve(static_cast<std::size_t>(totalParticles));
    st.particleVy.reserve(static_cast<std::size_t>(totalParticles));

    for (std::uint32_t c = 0; c < static_cast<std::uint32_t>(nc); ++c) {
        const std::uint32_t n = st.count[c];
        if (n == 0u) continue;
        const double mp = st.cellMass[c] / static_cast<double>(n);
        const double ux = 0.05 * std::sin(0.013 * static_cast<double>(c));
        const double uy = 0.05 * std::cos(0.017 * static_cast<double>(c));
        for (std::uint32_t j = 0; j < n; ++j) {
            st.particleCell.push_back(c);
            const bool latent = (j > 0u) && (((c + 17u * j) % 19u) == 0u);
            st.particleRole.push_back(static_cast<std::uint8_t>(latent ? 1u : 0u));
            st.particleMass.push_back(mp * (1.0 + 0.02 * static_cast<double>(static_cast<int>(j % 5u) - 2)));
            st.particleVx.push_back(ux + 0.001 * static_cast<double>(static_cast<int>(j % 7u) - 3));
            st.particleVy.push_back(uy - 0.001 * static_cast<double>(static_cast<int>((j + 2u) % 7u) - 3));
        }
    }
    return st;
}

void cpu_apply_shadow_transfers(
    const std::vector<std::uint32_t>& receiverCell,
    const std::vector<double>& requestedTransferMass,
    const std::vector<std::uint32_t>& selectedDonor,
    const std::vector<std::uint32_t>& insertionParticle,
    const mpcd::CudaResamplingShadowTransferParams& params,
    std::vector<std::uint32_t>& cell,
    std::vector<std::uint8_t>& role,
    std::vector<double>& mass,
    std::vector<double>& vx,
    std::vector<double>& vy,
    std::vector<double>& actual)
{
    actual.assign(receiverCell.size(), 0.0);
    for (std::size_t t = 0; t < receiverCell.size(); ++t) {
        const std::uint32_t p = selectedDonor[t];
        const std::uint32_t q = insertionParticle[t];
        if (p == params.invalidParticle || q == params.invalidParticle) continue;
        if (p >= cell.size() || q >= cell.size()) continue;
        if (role[p] != params.fluidRole || role[q] != params.insertionRole) continue;
        const double donorMass = mass[p];
        double dm = requestedTransferMass[t];
        if (!(dm > 0.0) || !(donorMass > params.minDonorMassAfterExtract)) continue;
        if (params.maxExtractFractionOfDonor > 0.0 && params.maxExtractFractionOfDonor < 1.0) {
            dm = std::min(dm, params.maxExtractFractionOfDonor * donorMass);
        }
        dm = std::min(dm, donorMass - params.minDonorMassAfterExtract);
        if (!(dm > 0.0)) continue;
        const double vxp = vx[p];
        const double vyp = vy[p];
        mass[p] -= dm;
        mass[q] += dm;
        cell[q] = receiverCell[t];
        role[q] = params.fluidRole;
        vx[q] = vxp;
        vy[q] = vyp;
        actual[t] = dm;
    }
}

double max_abs_diff(const std::vector<double>& a, const std::vector<double>& b) {
    if (a.size() != b.size()) return std::numeric_limits<double>::infinity();
    double out = 0.0;
    for (std::size_t i = 0; i < a.size(); ++i) out = std::max(out, std::abs(a[i] - b[i]));
    return out;
}

std::uint64_t mismatch_u32(const std::vector<std::uint32_t>& a, const std::vector<std::uint32_t>& b) {
    if (a.size() != b.size()) return static_cast<std::uint64_t>(std::max(a.size(), b.size()));
    std::uint64_t n = 0;
    for (std::size_t i = 0; i < a.size(); ++i) if (a[i] != b[i]) ++n;
    return n;
}

std::uint64_t mismatch_u8(const std::vector<std::uint8_t>& a, const std::vector<std::uint8_t>& b) {
    if (a.size() != b.size()) return static_cast<std::uint64_t>(std::max(a.size(), b.size()));
    std::uint64_t n = 0;
    for (std::size_t i = 0; i < a.size(); ++i) if (a[i] != b[i]) ++n;
    return n;
}

void totals(const std::vector<double>& m, const std::vector<double>& vx, const std::vector<double>& vy,
            double& mass, double& px, double& py) {
    mass = px = py = 0.0;
    for (std::size_t i = 0; i < m.size(); ++i) { mass += m[i]; px += m[i] * vx[i]; py += m[i] * vy[i]; }
}

} // namespace

int main() {
    const auto cases = parse_cases(std::getenv("GRID_CASES"));
    const std::string outPath = std::getenv("OUT_CSV") ? std::getenv("OUT_CSV") :
        "dev_history/artifacts/gpu_cuda_resampling_0233/cuda_resampling_shadow_transfer_smoke_0233.csv";
    std::ofstream csv(outPath);
    csv << std::setprecision(17);
    csv << "case,Nx,Ny,gamma,cells,particles,rawTransfers,shadowTransfers,requestedMass,actualMass,";
    csv << "appliedTransfers,skippedTransfers,duplicateDonorParticles,duplicateInsertionParticles,";
    csv << "cellMismatches,roleMismatches,massMaxAbs,vxMaxAbs,vyMaxAbs,actualMaxAbs,";
    csv << "massConservationAbs,pxConservationAbs,pyConservationAbs,";
    csv << "cpuGpuMassDiff,cpuGpuPxDiff,cpuGpuPyDiff,uploadSeconds,kernelSeconds,downloadSeconds,totalSeconds,verdict\n";

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
        std::vector<std::uint32_t> selected;
        std::vector<double> selectedMass;
        mpcd::CudaResamplingParticleSelectDiagnostics selectDiag;
        mpcd::cuda_resampling_select_donor_particles_0232(
            st.particleCell, st.particleRole, st.particleMass, static_cast<std::uint32_t>(nc),
            donor, transferMass, selectParams, selected, selectedMass, nullptr, &selectDiag);

        std::vector<std::uint32_t> filteredReceiver;
        std::vector<double> filteredTransferMass;
        std::vector<std::uint32_t> filteredSelected;
        std::vector<std::uint32_t> insertionParticle;
        std::unordered_set<std::uint32_t> usedDonor;
        std::unordered_set<std::uint32_t> usedReceiver;
        for (std::size_t t = 0; t < donor.size(); ++t) {
            const std::uint32_t p = selected[t];
            const std::uint32_t r = receiver[t];
            if (p == selectParams.invalidParticle) continue;
            if (!usedDonor.insert(p).second) continue;
            if (!usedReceiver.insert(r).second) continue;
            if (!(selectedMass[t] > 1.0e-9)) continue;
            filteredReceiver.push_back(r);
            filteredSelected.push_back(p);
            filteredTransferMass.push_back(std::min(transferMass[t], 0.45 * selectedMass[t]));
            const std::uint32_t q = static_cast<std::uint32_t>(st.particleCell.size());
            insertionParticle.push_back(q);
            st.particleCell.push_back(r);
            st.particleRole.push_back(1u);
            st.particleMass.push_back(0.0);
            st.particleVx.push_back(0.0);
            st.particleVy.push_back(0.0);
        }

        std::vector<std::uint32_t> cpuCell = st.particleCell;
        std::vector<std::uint8_t> cpuRole = st.particleRole;
        std::vector<double> cpuMass = st.particleMass, cpuVx = st.particleVx, cpuVy = st.particleVy, cpuActual;
        mpcd::CudaResamplingShadowTransferParams transferParams;
        transferParams.maxExtractFractionOfDonor = 0.50;
        cpu_apply_shadow_transfers(filteredReceiver, filteredTransferMass, filteredSelected, insertionParticle,
                                   transferParams, cpuCell, cpuRole, cpuMass, cpuVx, cpuVy, cpuActual);

        std::vector<std::uint32_t> gpuCell;
        std::vector<std::uint8_t> gpuRole;
        std::vector<double> gpuMass, gpuVx, gpuVy, gpuActual;
        mpcd::CudaResamplingShadowTransferDiagnostics diag;
        mpcd::cuda_resampling_apply_shadow_transfers_0233(
            st.particleCell, st.particleRole, st.particleMass, st.particleVx, st.particleVy,
            filteredReceiver, filteredTransferMass, filteredSelected, insertionParticle, transferParams,
            gpuCell, gpuRole, gpuMass, gpuVx, gpuVy, &gpuActual, &diag);

        const auto cellMis = mismatch_u32(cpuCell, gpuCell);
        const auto roleMis = mismatch_u8(cpuRole, gpuRole);
        const double massDiff = max_abs_diff(cpuMass, gpuMass);
        const double vxDiff = max_abs_diff(cpuVx, gpuVx);
        const double vyDiff = max_abs_diff(cpuVy, gpuVy);
        const double actualDiff = max_abs_diff(cpuActual, gpuActual);
        double m0, px0, py0, mc, pxc, pyc, mg, pxg, pyg;
        totals(st.particleMass, st.particleVx, st.particleVy, m0, px0, py0);
        totals(cpuMass, cpuVx, cpuVy, mc, pxc, pyc);
        totals(gpuMass, gpuVx, gpuVy, mg, pxg, pyg);
        const double massCons = std::abs(mc - m0);
        const double pxCons = std::abs(pxc - px0);
        const double pyCons = std::abs(pyc - py0);
        const double cpuGpuMass = std::abs(mc - mg);
        const double cpuGpuPx = std::abs(pxc - pxg);
        const double cpuGpuPy = std::abs(pyc - pyg);

        const bool pass = filteredReceiver.size() > 0 && cellMis == 0 && roleMis == 0 &&
                          massDiff <= 1e-10 && vxDiff <= 1e-12 && vyDiff <= 1e-12 && actualDiff <= 1e-12 &&
                          massCons <= 1e-8 && pxCons <= 1e-8 && pyCons <= 1e-8 &&
                          cpuGpuMass <= 1e-10 && cpuGpuPx <= 1e-10 && cpuGpuPy <= 1e-10 &&
                          diag.appliedTransfers == filteredReceiver.size() &&
                          diag.duplicateDonorParticles == 0u && diag.duplicateInsertionParticles == 0u;
        allPass = allPass && pass;
        const std::string label = std::to_string(cs.nx) + "x" + std::to_string(cs.ny) + "_g" + std::to_string(cs.gamma);
        csv << label << ',' << cs.nx << ',' << cs.ny << ',' << cs.gamma << ',' << nc << ',' << st.particleCell.size() << ','
            << planDiag.transfers << ',' << filteredReceiver.size() << ',' << diag.requestedTransferMass << ',' << diag.actualTransferMass << ','
            << diag.appliedTransfers << ',' << diag.skippedTransfers << ',' << diag.duplicateDonorParticles << ',' << diag.duplicateInsertionParticles << ','
            << cellMis << ',' << roleMis << ',' << massDiff << ',' << vxDiff << ',' << vyDiff << ',' << actualDiff << ','
            << massCons << ',' << pxCons << ',' << pyCons << ',' << cpuGpuMass << ',' << cpuGpuPx << ',' << cpuGpuPy << ','
            << diag.uploadSeconds << ',' << diag.kernelSeconds << ',' << diag.downloadSeconds << ',' << diag.totalSeconds << ','
            << (pass ? "PASS" : "FAIL") << '\n';

        std::cout << "[0233-resampling-shadow-transfer] " << (pass ? "PASS " : "FAIL ") << label
                  << " rawTransfers=" << planDiag.transfers
                  << " shadowTransfers=" << filteredReceiver.size()
                  << " actualMass=" << diag.actualTransferMass
                  << " mismatches=" << (cellMis + roleMis)
                  << " massMaxAbs=" << massDiff
                  << "\n";
    }
    std::cout << "[0233-resampling-shadow-transfer] wrote " << outPath << "\n";
    return allPass ? 0 : 1;
}
