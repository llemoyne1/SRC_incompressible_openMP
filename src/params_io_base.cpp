#include "params_io_base.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unordered_map>

namespace mpcd {
namespace {

std::string trim(std::string s) {
    auto not_space = [](unsigned char c) { return !std::isspace(c); };
    s.erase(s.begin(), std::find_if(s.begin(), s.end(), not_space));
    s.erase(std::find_if(s.rbegin(), s.rend(), not_space).base(), s.end());
    return s;
}

std::string lower(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return s;
}

bool parse_bool(const std::string& value, const std::string& key) {
    const std::string v = lower(trim(value));
    if (v == "true" || v == "1" || v == "yes" || v == "on") {
        return true;
    }
    if (v == "false" || v == "0" || v == "no" || v == "off") {
        return false;
    }
    throw std::runtime_error("Invalid boolean value for key '" + key + "': " + value);
}

double parse_double(const std::string& value, const std::string& key) {
    std::size_t pos = 0u;
    const std::string v = trim(value);
    const double out = std::stod(v, &pos);
    if (pos != v.size()) {
        throw std::runtime_error("Invalid floating-point value for key '" + key + "': " + value);
    }
    return out;
}

int parse_int(const std::string& value, const std::string& key) {
    std::size_t pos = 0u;
    const std::string v = trim(value);
    const int out = std::stoi(v, &pos);
    if (pos != v.size()) {
        throw std::runtime_error("Invalid integer value for key '" + key + "': " + value);
    }
    return out;
}

std::uint64_t parse_u64(const std::string& value, const std::string& key) {
    std::size_t pos = 0u;
    const std::string v = trim(value);
    const unsigned long long out = std::stoull(v, &pos);
    if (pos != v.size()) {
        throw std::runtime_error("Invalid unsigned integer value for key '" + key + "': " + value);
    }
    return static_cast<std::uint64_t>(out);
}

bool has_key(const std::unordered_map<std::string, std::string>& kv, const std::string& key) {
    return kv.find(key) != kv.end();
}

std::string get_lower(const std::unordered_map<std::string, std::string>& kv, const std::string& key) {
    return lower(trim(kv.at(key)));
}

bool is_wall_mode(const std::string& mode) {
    return mode == "specular" || mode == "bounceback";
}

bool is_reserved_io_mode(const std::string& mode) {
    return mode == "inlet" || mode == "input" || mode == "outlet" || mode == "output" || mode == "open";
}

bool is_known_boundary_mode(const std::string& mode) {
    return mode == "periodic" || is_wall_mode(mode) || is_reserved_io_mode(mode);
}

} // namespace

SimulationParams read_simulation_params_kv(const std::string& filepath) {
    std::ifstream in(filepath);
    if (!in) {
        throw std::runtime_error("Cannot open parameter file: " + filepath);
    }

    std::unordered_map<std::string, std::string> kv;
    std::string line;
    int lineNo = 0;
    while (std::getline(in, line)) {
        ++lineNo;
        const std::size_t comment = line.find('#');
        if (comment != std::string::npos) {
            line = line.substr(0, comment);
        }
        line = trim(line);
        if (line.empty()) {
            continue;
        }

        std::string key;
        std::string value;
        const std::size_t eq = line.find('=');
        if (eq != std::string::npos) {
            key = trim(line.substr(0, eq));
            value = trim(line.substr(eq + 1u));
        } else {
            std::istringstream iss(line);
            iss >> key;
            std::getline(iss, value);
            value = trim(value);
        }

        if (key.empty() || value.empty()) {
            throw std::runtime_error("Malformed parameter line " + std::to_string(lineNo) + " in " + filepath);
        }
        kv[key] = value;
    }

    SimulationParams p{};
    for (const auto& item : kv) {
        const std::string& key = item.first;
        const std::string& value = item.second;

        if (key == "inputState") p.inputState = value;
        else if (key == "outputDir") p.outputDir = value;
        else if (key == "Lx") p.Lx = parse_double(value, key);
        else if (key == "Ly") p.Ly = parse_double(value, key);
        else if (key == "Nx") p.Nx = parse_int(value, key);
        else if (key == "Ny") p.Ny = parse_int(value, key);
        else if (key == "dt") p.dt = parse_double(value, key);
        else if (key == "nSteps") p.nSteps = parse_int(value, key);
        else if (key == "rotationAngle") p.rotationAngle = parse_double(value, key);
        else if (key == "alphaDeg") p.rotationAngle = parse_double(value, key) * 3.141592653589793238462643383279502884 / 180.0;
        else if (key == "randomRotationSign") p.randomRotationSign = parse_bool(value, key);
        else if (key == "gridShiftEnable") p.gridShiftEnable = parse_bool(value, key);
        else if (key == "rngSeed") p.rngSeed = parse_u64(value, key);
        else if (key == "bodyAccelerationX") p.bodyAccelerationX = parse_double(value, key);
        else if (key == "bodyAccelerationY") p.bodyAccelerationY = parse_double(value, key);
        else if (key == "bodyForceX") p.bodyAccelerationX = parse_double(value, key);
        else if (key == "bodyForceY") p.bodyAccelerationY = parse_double(value, key);
        else if (key == "bcX" || key == "bcY" ||
                 key == "bcLeft" || key == "bcRight" ||
                 key == "bcBottom" || key == "bcTop" ||
                 key == "boundaryLeft" || key == "boundaryRight" ||
                 key == "boundaryBottom" || key == "boundaryTop") {
            // Applied after the generic loop so per-face keys override pair aliases.
        }
        else if (key == "wallVpEnable") p.wallVpEnable = parse_bool(value, key);
        else if (key == "wallVpMode") p.wallVpMode = get_lower(kv, key);
        else if (key == "wallVpGamma") p.wallVpGamma = parse_double(value, key);
        else if (key == "wallVpMass") p.wallVpMass = parse_double(value, key);
        else if (key == "wallVpKBT") p.wallVpKBT = parse_double(value, key);
        else if (key == "wallVpUxLeft") p.wallVpUxLeft = parse_double(value, key);
        else if (key == "wallVpUyLeft") p.wallVpUyLeft = parse_double(value, key);
        else if (key == "wallVpUxRight") p.wallVpUxRight = parse_double(value, key);
        else if (key == "wallVpUyRight") p.wallVpUyRight = parse_double(value, key);
        else if (key == "wallVpUxBottom") p.wallVpUxBottom = parse_double(value, key);
        else if (key == "wallVpUyBottom") p.wallVpUyBottom = parse_double(value, key);
        else if (key == "wallVpUxTop") p.wallVpUxTop = parse_double(value, key);
        else if (key == "wallVpUyTop") p.wallVpUyTop = parse_double(value, key);
        else if (key == "thermostatEnable") p.thermostatEnable = parse_bool(value, key);
        else if (key == "thermostatMode") p.thermostatMode = get_lower(kv, key);
        else if (key == "thermostatEvery") p.thermostatEvery = parse_int(value, key);
        else if (key == "thermostatTargetKBT") p.thermostatTargetKBT = parse_double(value, key);
        else if (key == "thermostatMinParticles") p.thermostatMinParticles = parse_int(value, key);
        else if (key == "thermostatEpsilon") p.thermostatEpsilon = parse_double(value, key);
        else if (key == "kBT") p.kBT = parse_double(value, key);
        else if (key == "summaryEvery") p.summaryEvery = parse_int(value, key);
        else if (key == "dumpStateEvery") p.dumpStateEvery = parse_int(value, key);
        else if (key == "numThreads") p.numThreads = parse_int(value, key);
        else {
            throw std::runtime_error("Unknown parameter key in base SRC/MPCD executable: " + key);
        }
    }

    if (has_key(kv, "bcX")) {
        p.bcLeft = get_lower(kv, "bcX");
        p.bcRight = p.bcLeft;
    }
    if (has_key(kv, "bcY")) {
        p.bcBottom = get_lower(kv, "bcY");
        p.bcTop = p.bcBottom;
    }
    if (has_key(kv, "bcLeft")) p.bcLeft = get_lower(kv, "bcLeft");
    if (has_key(kv, "bcRight")) p.bcRight = get_lower(kv, "bcRight");
    if (has_key(kv, "bcBottom")) p.bcBottom = get_lower(kv, "bcBottom");
    if (has_key(kv, "bcTop")) p.bcTop = get_lower(kv, "bcTop");
    if (has_key(kv, "boundaryLeft")) p.bcLeft = get_lower(kv, "boundaryLeft");
    if (has_key(kv, "boundaryRight")) p.bcRight = get_lower(kv, "boundaryRight");
    if (has_key(kv, "boundaryBottom")) p.bcBottom = get_lower(kv, "boundaryBottom");
    if (has_key(kv, "boundaryTop")) p.bcTop = get_lower(kv, "boundaryTop");

    validate_simulation_params(p);
    return p;
}

bool is_x_periodic(const SimulationParams& p) {
    return p.bcLeft == "periodic" && p.bcRight == "periodic";
}

bool is_y_periodic(const SimulationParams& p) {
    return p.bcBottom == "periodic" && p.bcTop == "periodic";
}

void validate_simulation_params(const SimulationParams& p) {
    if (p.inputState.empty()) {
        throw std::runtime_error("Missing required parameter: inputState");
    }
    if (p.outputDir.empty()) {
        throw std::runtime_error("outputDir must not be empty");
    }
    if (!(p.Lx > 0.0) || !(p.Ly > 0.0)) {
        throw std::runtime_error("Lx and Ly must be positive");
    }
    if (p.Nx <= 0 || p.Ny <= 0) {
        throw std::runtime_error("Nx and Ny must be positive");
    }
    if (!(p.dt > 0.0)) {
        throw std::runtime_error("dt must be positive");
    }
    if (p.nSteps < 0) {
        throw std::runtime_error("nSteps must be non-negative");
    }
    if (!(p.rotationAngle == p.rotationAngle)) {
        throw std::runtime_error("rotationAngle is NaN");
    }

    const std::string modes[4] = {p.bcLeft, p.bcRight, p.bcBottom, p.bcTop};
    const std::string names[4] = {"bcLeft", "bcRight", "bcBottom", "bcTop"};
    for (int i = 0; i < 4; ++i) {
        if (!is_known_boundary_mode(modes[i])) {
            throw std::runtime_error("Unknown boundary mode for " + names[i] + ": " + modes[i]);
        }
        if (is_reserved_io_mode(modes[i])) {
            throw std::runtime_error("Boundary mode '" + modes[i] + "' for " + names[i] +
                                     " is reserved for future inlet/outlet support and is not implemented yet");
        }
    }

    const bool leftPeriodic = p.bcLeft == "periodic";
    const bool rightPeriodic = p.bcRight == "periodic";
    const bool bottomPeriodic = p.bcBottom == "periodic";
    const bool topPeriodic = p.bcTop == "periodic";
    if (leftPeriodic != rightPeriodic) {
        throw std::runtime_error("Periodic x boundaries must be paired: bcLeft and bcRight must both be periodic");
    }
    if (bottomPeriodic != topPeriodic) {
        throw std::runtime_error("Periodic y boundaries must be paired: bcBottom and bcTop must both be periodic");
    }
    if (!leftPeriodic && (!is_wall_mode(p.bcLeft) || !is_wall_mode(p.bcRight))) {
        throw std::runtime_error("Non-periodic x boundaries currently require wall modes: specular or bounceback");
    }
    if (!bottomPeriodic && (!is_wall_mode(p.bcBottom) || !is_wall_mode(p.bcTop))) {
        throw std::runtime_error("Non-periodic y boundaries currently require wall modes: specular or bounceback");
    }

    if (p.wallVpEnable) {
        if (p.wallVpMode != "stochastic_fraction") {
            throw std::runtime_error("wallVpMode currently supports only: stochastic_fraction");
        }
        if (is_x_periodic(p) && is_y_periodic(p)) {
            throw std::runtime_error("wallVpEnable=true requires at least one non-periodic wall pair");
        }
        if (!(p.wallVpGamma >= 0.0)) {
            throw std::runtime_error("wallVpGamma must be non-negative; use 0 to infer the mean real occupancy");
        }
        if (!(p.wallVpMass > 0.0)) {
            throw std::runtime_error("wallVpMass must be positive");
        }
        if (p.wallVpKBT < 0.0 && !(p.kBT > 0.0)) {
            throw std::runtime_error("wallVpKBT is negative, so kBT must be positive when wallVpEnable=true");
        }
        if (p.wallVpKBT == 0.0) {
            throw std::runtime_error("wallVpKBT must be positive, or negative to inherit kBT");
        }
    }

    if (p.thermostatEnable) {
        if (p.thermostatMode != "cell_relative_rescale") {
            throw std::runtime_error("thermostatMode currently supports only: cell_relative_rescale");
        }
        if (p.thermostatEvery <= 0) {
            throw std::runtime_error("thermostatEvery must be positive when thermostatEnable=true");
        }
        if (p.thermostatMinParticles < 2) {
            throw std::runtime_error("thermostatMinParticles must be at least 2");
        }
        if (!(p.thermostatEpsilon > 0.0)) {
            throw std::runtime_error("thermostatEpsilon must be positive");
        }
        if (p.thermostatTargetKBT < 0.0 && !(p.kBT > 0.0)) {
            throw std::runtime_error("thermostatTargetKBT is negative, so kBT must be positive when thermostatEnable=true");
        }
        if (p.thermostatTargetKBT == 0.0) {
            throw std::runtime_error("thermostatTargetKBT must be positive, or negative to inherit kBT");
        }
    }
    if (p.summaryEvery <= 0) {
        throw std::runtime_error("summaryEvery must be positive");
    }
    if (p.dumpStateEvery < 0) {
        throw std::runtime_error("dumpStateEvery must be non-negative");
    }
    if (p.numThreads < 0) {
        throw std::runtime_error("numThreads must be non-negative");
    }
}

} // namespace mpcd
