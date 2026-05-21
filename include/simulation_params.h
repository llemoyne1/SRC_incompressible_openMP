#pragma once

#include <cstdint>
#include <string>

namespace mpcd {

struct SimulationParams {
    std::string inputState;
    std::string outputDir = "run_base";

    double Lx = 1.0;
    double Ly = 1.0;
    int Nx = 32;
    int Ny = 32;

    double dt = 1.0e-3;
    int nSteps = 1000;

    // Rotation angle in radians. alphaDeg is accepted by the parser as a convenience alias.
    double rotationAngle = 2.0943951023931953; // 120 deg
    bool randomRotationSign = true;

    bool gridShiftEnable = true;
    std::uint64_t rngSeed = 12345u;

    // Uniform body acceleration applied before streaming. The parser also accepts
    // bodyForceX/bodyForceY as aliases for compatibility with previous parameter files.
    double bodyAccelerationX = 0.0;
    double bodyAccelerationY = 0.0;

    // Only periodic boundaries are implemented in this first SRC/MPCD base executable.
    std::string bcX = "periodic";
    std::string bcY = "periodic";

    // Placeholder for future work. The base executable rejects thermostatEnable=true
    // until a mass-aware thermostat is implemented explicitly.
    bool thermostatEnable = false;
    double kBT = 0.0;

    int summaryEvery = 10;
    int dumpStateEvery = 0;

    // If >0 and OpenMP is enabled, the executable calls omp_set_num_threads(numThreads).
    int numThreads = 0;
};

void validate_simulation_params(const SimulationParams& params);

} // namespace mpcd
