#include "cuda_particle_state.h"
#include "particle_state.h"

#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

using namespace mpcd;

namespace {

struct Args {
    int nx = 64;
    int ny = 64;
    int gamma = 20;
    int cycles = 20;
    int threads = 256;
    double dvx = 1.0e-5;
    double dvy = -2.0e-5;
    double tolerance = 1.0e-12;
    int mixedRoles = 1;
    int variableMass = 1;
    std::string outCsv;
    bool append = false;
};

int parse_int(const std::string& s) { return std::stoi(s); }
double parse_double(const std::string& s) { return std::stod(s); }

Args parse_args(int argc, char** argv) {
    Args a;
    for (int i = 1; i < argc; ++i) {
        const std::string k = argv[i];
        auto need = [&](const char* name) -> std::string {
            if (i + 1 >= argc) throw std::runtime_error(std::string("missing value for ") + name);
            return argv[++i];
        };
        if (k == "--nx") a.nx = parse_int(need("--nx"));
        else if (k == "--ny") a.ny = parse_int(need("--ny"));
        else if (k == "--gamma") a.gamma = parse_int(need("--gamma"));
        else if (k == "--cycles") a.cycles = parse_int(need("--cycles"));
        else if (k == "--threads") a.threads = parse_int(need("--threads"));
        else if (k == "--dvx") a.dvx = parse_double(need("--dvx"));
        else if (k == "--dvy") a.dvy = parse_double(need("--dvy"));
        else if (k == "--tolerance") a.tolerance = parse_double(need("--tolerance"));
        else if (k == "--mixed-roles") a.mixedRoles = parse_int(need("--mixed-roles"));
        else if (k == "--variable-mass") a.variableMass = parse_int(need("--variable-mass"));
        else if (k == "--out-csv") a.outCsv = need("--out-csv");
        else if (k == "--append") a.append = true;
        else throw std::runtime_error("unknown argument: " + k);
    }
    return a;
}

ParticleState make_state(const Args& a) {
    if (a.nx <= 0 || a.ny <= 0 || a.gamma <= 0) throw std::runtime_error("invalid grid/gamma");
    const std::uint64_t n = static_cast<std::uint64_t>(a.nx) * static_cast<std::uint64_t>(a.ny) * static_cast<std::uint64_t>(a.gamma);
    ParticleState s;
    s.Np = n;
    s.dim = 2u;
    const std::size_t nn = static_cast<std::size_t>(n);
    s.x.resize(nn);
    s.y.resize(nn);
    s.vx.resize(nn);
    s.vy.resize(nn);
    s.mass.resize(nn);
    s.type.resize(nn, 0u);
    s.role.resize(nn, kParticleRoleFluid);

    const double pi = 3.141592653589793238462643383279502884;
    for (std::size_t i = 0; i < nn; ++i) {
        const std::size_t cell = i / static_cast<std::size_t>(a.gamma);
        const int ix = static_cast<int>(cell % static_cast<std::size_t>(a.nx));
        const int iy = static_cast<int>(cell / static_cast<std::size_t>(a.nx));
        const double frac = static_cast<double>((i % static_cast<std::size_t>(a.gamma)) + 1u) / static_cast<double>(a.gamma + 1);
        s.x[i] = (static_cast<double>(ix) + frac) / static_cast<double>(a.nx);
        s.y[i] = (static_cast<double>(iy) + 1.0 - frac) / static_cast<double>(a.ny);
        const double theta = 2.0 * pi * (static_cast<double>(ix) / std::max(1, a.nx) + 0.37 * static_cast<double>(iy) / std::max(1, a.ny));
        const int rem11 = static_cast<int>(i % 11u);
        const int rem13 = static_cast<int>(i % 13u);
        s.vx[i] = 0.1 * std::sin(theta) + 0.001 * static_cast<double>(rem11 - 5);
        s.vy[i] = 0.1 * std::cos(theta) - 0.001 * static_cast<double>(rem13 - 6);
        s.mass[i] = a.variableMass ? (1.0 + 0.01 * static_cast<double>(i % 7u)) : 1.0;
        s.type[i] = static_cast<std::uint32_t>(i % 3u);
        if (a.mixedRoles) {
            if (i % 31u == 0u) s.role[i] = kParticleRoleInactive;
            else if (i % 17u == 0u) s.role[i] = kParticleRoleLatent;
        }
    }
    validate_particle_state(s, "make_state(0218)");
    return s;
}

void write_csv(const std::string& path, const Args& a, const CudaParticleStateSmokeResult& r) {
    if (path.empty()) return;
    const bool writeHeader = !a.append;
    std::ofstream f(path, a.append ? std::ios::app : std::ios::out);
    if (!f) throw std::runtime_error("failed to open output CSV: " + path);
    f << std::setprecision(17);
    if (writeHeader) {
        f << "case,Nx,Ny,gamma,particles,fluidParticles,latentParticles,inactiveParticles,cycles,pass,"
             "maxAbsX,maxAbsY,maxAbsVx,maxAbsVy,rmsV,velocityMismatches,"
             "allocationCalls,reusedAllocation,capacity,allocatedBytes,hostToDeviceBytes,deviceToHostBytes,"
             "uploadCalls,downloadCalls,allocateSeconds,uploadSeconds,kernelSeconds,downloadSeconds,totalSeconds\n";
    }
    f << a.nx << "x" << a.ny << "_g" << a.gamma << "_c" << a.cycles << ","
      << a.nx << "," << a.ny << "," << a.gamma << ","
      << r.particles << "," << r.fluidParticles << "," << r.latentParticles << "," << r.inactiveParticles << ","
      << r.cycles << "," << r.pass << ","
      << r.maxAbsX << "," << r.maxAbsY << "," << r.maxAbsVx << "," << r.maxAbsVy << ","
      << r.rmsV << "," << r.velocityMismatches << ","
      << r.diagnostics.allocationCalls << "," << r.diagnostics.reusedAllocation << ","
      << r.diagnostics.capacity << "," << r.diagnostics.allocatedBytes << ","
      << r.diagnostics.hostToDeviceBytes << "," << r.diagnostics.deviceToHostBytes << ","
      << r.diagnostics.uploadCalls << "," << r.diagnostics.downloadCalls << ","
      << r.diagnostics.allocateSeconds << "," << r.diagnostics.uploadSeconds << ","
      << r.diagnostics.kernelSeconds << "," << r.diagnostics.downloadSeconds << ","
      << r.diagnostics.totalSeconds << "\n";
}

} // namespace

int main(int argc, char** argv) {
    try {
        const Args a = parse_args(argc, argv);
        if (!cuda_particle_state_available()) {
            std::cerr << "CUDA_PARTICLE_STATE_0218 FAIL: no CUDA device or backend not enabled\n";
            return 2;
        }
        const ParticleState s = make_state(a);
        const CudaParticleStateSmokeResult r = cuda_particle_state_smoke_roundtrip(s, a.cycles, a.dvx, a.dvy, a.threads, a.tolerance);
        write_csv(a.outCsv, a, r);
        std::cout << std::setprecision(17)
                  << "CUDA_PARTICLE_STATE_0218 " << (r.pass ? "PASS" : "FAIL")
                  << " Nx=" << a.nx
                  << " Ny=" << a.ny
                  << " gamma=" << a.gamma
                  << " particles=" << r.particles
                  << " fluidParticles=" << r.fluidParticles
                  << " cycles=" << r.cycles
                  << " maxAbsVx=" << r.maxAbsVx
                  << " maxAbsVy=" << r.maxAbsVy
                  << " velocityMismatches=" << r.velocityMismatches
                  << " allocationCalls=" << r.diagnostics.allocationCalls
                  << " reusedAllocation=" << r.diagnostics.reusedAllocation
                  << " uploadSeconds=" << r.diagnostics.uploadSeconds
                  << " kernelSeconds=" << r.diagnostics.kernelSeconds
                  << " downloadSeconds=" << r.diagnostics.downloadSeconds
                  << " totalSeconds=" << r.diagnostics.totalSeconds
                  << "\n";
        return r.pass ? 0 : 1;
    } catch (const std::exception& e) {
        std::cerr << "CUDA_PARTICLE_STATE_0218 ERROR: " << e.what() << "\n";
        return 3;
    }
}
