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

    // Boundary modes are specified per face. The legacy aliases bcX and bcY are
    // still accepted by the parser and set the corresponding face pairs.
    // Implemented now: periodic pairs, specular walls, bounceback walls.
    // Reserved for future internal-flow simulations: inlet, outlet.
    std::string bcLeft = "periodic";
    std::string bcRight = "periodic";
    std::string bcBottom = "periodic";
    std::string bcTop = "periodic";

    // Virtual wall particles are not stored in the particle state. When enabled,
    // they are sampled as aggregate mass/momentum contributions to boundary-cut
    // collision cells. This is the first wall-coupling layer before explicit
    // geometry/cylinder virtual particles.
    bool wallVpEnable = false;
    std::string wallVpMode = "stochastic_fraction";
    double wallVpGamma = 0.0; // expected VP count in a fully solid collision cell; 0 => mean real occupancy
    double wallVpMass = 1.0;
    double wallVpKBT = -1.0;  // negative => use kBT
    double wallVpUxLeft = 0.0;
    double wallVpUyLeft = 0.0;
    double wallVpUxRight = 0.0;
    double wallVpUyRight = 0.0;
    double wallVpUxBottom = 0.0;
    double wallVpUyBottom = 0.0;
    double wallVpUxTop = 0.0;
    double wallVpUyTop = 0.0;

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

bool is_x_periodic(const SimulationParams& params);
bool is_y_periodic(const SimulationParams& params);

} // namespace mpcd
