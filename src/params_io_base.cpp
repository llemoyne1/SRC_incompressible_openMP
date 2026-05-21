#include "params_io_base.h"

#include <algorithm>
#include <cctype>
#include <cmath>
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
    const double out = std::stod(value, &pos);
    if (pos != trim(value).size()) {
        throw std::runtime_error("Invalid floating-point value for key '" + key + "': " + value);
    }
    return out;
}

int parse_int(const std::string& value, const std::string& key) {
    std::size_t pos = 0u;
    const int out = std::stoi(value, &pos);
    if (pos != trim(value).size()) {
        throw std::runtime_error("Invalid integer value for key '" + key + "': " + value);
    }
    return out;
}

std::uint64_t parse_u64(const std::string& value, const std::string& key) {
    std::size_t pos = 0u;
    const unsigned long long out = std::stoull(value, &pos);
    if (pos != trim(value).size()) {
        throw std::runtime_error("Invalid unsigned integer value for key '" + key + "': " + value);
    }
    return static_cast<std::uint64_t>(out);
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
        else if (key == "bcX") p.bcX = lower(value);
        else if (key == "bcY") p.bcY = lower(value);
        else if (key == "thermostatEnable") p.thermostatEnable = parse_bool(value, key);
        else if (key == "kBT") p.kBT = parse_double(value, key);
        else if (key == "summaryEvery") p.summaryEvery = parse_int(value, key);
        else if (key == "dumpStateEvery") p.dumpStateEvery = parse_int(value, key);
        else if (key == "numThreads") p.numThreads = parse_int(value, key);
        else {
            throw std::runtime_error("Unknown parameter key in base SRC/MPCD executable: " + key);
        }
    }

    validate_simulation_params(p);
    return p;
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
    if (p.bcX != "periodic" || p.bcY != "periodic") {
        throw std::runtime_error("The first base executable supports only bcX=periodic and bcY=periodic");
    }
    if (p.thermostatEnable) {
        throw std::runtime_error("thermostatEnable=true is not implemented yet in the mass-aware base executable");
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
