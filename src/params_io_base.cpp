#include "params_io_base.h"
#include "open_boundary_segments.h"
#include "q6_species_distribution_0491a.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>

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
    if (!v.empty() && v.front() == '-') {
        throw std::runtime_error("Invalid negative unsigned integer value for key '" + key + "': " + value);
    }
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
    return mode == "solid" || mode == "specular" || mode == "bounceback";
}

bool is_reserved_io_mode(const std::string& mode) {
    return is_io_boundary_mode(mode);
}

bool is_known_boundary_mode(const std::string& mode) {
    return mode == "periodic" || is_wall_mode(mode) || is_reserved_io_mode(mode);
}


bool is_removed_open_aperture_key(const std::string& key) {
    return key == "openBoundaryApertureEnable" || key == "ioApertureEnable" ||
           key == "leftOpenYMin" || key == "inletLeftYMin" ||
           key == "leftOpenYMax" || key == "inletLeftYMax" ||
           key == "rightOpenYMin" || key == "outletRightYMin" ||
           key == "rightOpenYMax" || key == "outletRightYMax" ||
           key == "bottomOpenXMin" || key == "inletBottomXMin" ||
           key == "bottomOpenXMax" || key == "inletBottomXMax" ||
           key == "topOpenXMin" || key == "outletTopXMin" ||
           key == "topOpenXMax" || key == "outletTopXMax";
}

bool parse_species_resampling_enable_key(const std::string& key, int* speciesIndex) {
    const std::string prefix = "species";
    const std::string suffix = "ResamplingEnable";
    if (key.rfind(prefix, 0) != 0 || key.size() <= prefix.size() + suffix.size() ||
        key.compare(key.size() - suffix.size(), suffix.size(), suffix) != 0) {
        return false;
    }
    const std::string indexText = key.substr(
        prefix.size(), key.size() - prefix.size() - suffix.size());
    if (indexText.empty() ||
        !std::all_of(indexText.begin(), indexText.end(),
                     [](unsigned char c) { return std::isdigit(c); })) {
        return false;
    }
    const long long value = std::stoll(indexText);
    if (value < 0 || value > static_cast<long long>(std::numeric_limits<int>::max())) {
        throw std::runtime_error(key + ": species index exceeds int range");
    }
    if (speciesIndex != nullptr) *speciesIndex = static_cast<int>(value);
    return true;
}

bool is_species_definition_key(const std::string& key) {
    const std::string prefix = "species";
    if (key.rfind(prefix, 0) != 0) return false;
    if (key == "speciesRegistryEnable" || key == "speciesCount" ||
        key == "speciesRequireRegisteredTypes" || key == "speciesDiagnosticsEnable" ||
        key == "speciesDiagnosticsFilename" || key == "speciesCellDiagnosticsEnable" ||
        key == "speciesCellDiagnosticsFilename" ||
        key == "speciesCellCudaDepositEnable" ||
        key == "speciesCellCudaComparisonFilename" ||
        key == "speciesCellCudaComparisonTolerance" ||
        key == "speciesCellCudaThreadsPerBlock" ||
        key == "speciesQ6Enable" ||
        key == "speciesQ6Mode" ||
        key == "speciesQ6Sensitivity" ||
        key == "speciesQ6AlphaEpsilon" ||
        key == "speciesQ6FallbackMode" ||
        key == "speciesQ6ComparisonTolerance" ||
        key == "speciesQ6MinOccupancyFraction" ||
        key == "speciesResamplingMassClosureEnable" ||
        key == "speciesResamplingMassClosureCudaEnable" ||
        key == "speciesMassClosureCudaDiagnosticsFilename" ||
        key == "speciesMassClosureCudaComparisonTolerance" ||
        key == "speciesResamplingPopulationGuardEnable" ||
        key == "speciesResamplingPopulationGuardCudaEnable" ||
        key == "speciesResamplingTransferEnable" ||
        key == "speciesResamplingTransferCudaEnable" ||
        key == "speciesTransferCudaDiagnosticsFilename" ||
        key == "speciesTransferCudaComparisonTolerance" ||
        key == "speciesResamplingCudaResidentValidationEnable" ||
        key == "speciesResamplingCudaResidentFastPathEnable" ||
        key == "speciesCudaResidentFastPathDiagnosticsFilename" ||
        key == "speciesResamplingCudaResidentDepositsEnable" ||
        key == "speciesResamplingCudaResidentPoolEnable" ||
        key == "speciesResamplingCudaResidentMaintenanceStrict" ||
        key == "speciesCudaResidentMaintenanceDiagnosticsFilename" ||
        key == "cudaResamplingEmptyRefillSpeciesCompositionEnable") {
        return false;
    }
    const std::string suffix = key.substr(prefix.size());
    if (suffix.empty()) return false;
    return std::all_of(suffix.begin(), suffix.end(), [](unsigned char c) { return std::isdigit(c); });
}

SpeciesDefinition parse_species_definition_value(const std::string& value,
                                                 const std::string& key) {
    std::istringstream iss(value);
    long long typeValue = 0;
    SpeciesDefinition d{};
    std::string phase;
    if (!(iss >> typeValue >> d.name >> phase >> d.q6StrengthDeclared >>
          d.resamplingMassClosureStrengthDeclared)) {
        throw std::runtime_error(
            "Malformed " + key +
            ": expected 'type name phaseFamily q6StrengthDeclared massClosureStrengthDeclared [referenceCellMassDeclared]'");
    }
    std::string optionalReferenceMass;
    if (iss >> optionalReferenceMass) {
        std::size_t consumed = 0u;
        try {
            d.referenceCellMassDeclared = std::stod(optionalReferenceMass, &consumed);
        } catch (const std::exception&) {
            throw std::runtime_error("Malformed " + key + ": invalid referenceCellMassDeclared");
        }
        if (consumed != optionalReferenceMass.size()) {
            throw std::runtime_error("Malformed " + key + ": invalid referenceCellMassDeclared");
        }
        std::string extra;
        if (iss >> extra) {
            throw std::runtime_error("Malformed " + key + ": too many fields");
        }
    }
    if (typeValue < 0 || typeValue > static_cast<long long>(std::numeric_limits<std::uint32_t>::max())) {
        throw std::runtime_error(key + ": type must be a non-negative uint32 value");
    }
    d.type = static_cast<std::uint32_t>(typeValue);
    d.phaseFamily = parse_species_phase_family(phase, key);
    return d;
}

bool is_open_boundary_segment_key(const std::string& key) {
    const std::string prefix = "openBoundarySegment";
    if (key.rfind(prefix, 0) != 0) return false;
    if (key == "openBoundarySegmentsEnable" || key == "openBoundarySegmentCount") return false;
    const std::string suffix = key.substr(prefix.size());
    if (suffix.empty()) return false;
    return std::all_of(suffix.begin(), suffix.end(), [](unsigned char c) { return std::isdigit(c); });
}

OpenBoundarySegment parse_open_boundary_segment_value(const std::string& value,
                                                      const std::string& key) {
    std::istringstream iss(value);
    OpenBoundarySegment seg{};
    long long typeValue = 0;
    if (!(iss >> seg.face >> seg.mode >> seg.sMin >> seg.sMax >> seg.ux >> seg.uy >> typeValue >> seg.mass)) {
        throw std::runtime_error("Malformed " + key + ": expected 'face mode sMin sMax ux uy type mass'");
    }
    std::string extra;
    if (iss >> extra) {
        throw std::runtime_error("Malformed " + key + ": too many fields; expected exactly 'face mode sMin sMax ux uy type mass'");
    }
    seg.face = lower(trim(seg.face));
    seg.mode = lower(trim(seg.mode));
    std::replace(seg.face.begin(), seg.face.end(), '-', '_');
    std::replace(seg.mode.begin(), seg.mode.end(), '-', '_');
    if (seg.face != "left" && seg.face != "right" && seg.face != "bottom" && seg.face != "top") {
        throw std::runtime_error(key + ": face must be left, right, bottom or top");
    }
    if (!is_io_boundary_mode(seg.mode)) {
        throw std::runtime_error(key + ": mode must be inlet or outlet");
    }
    if (!std::isfinite(seg.sMin) || !std::isfinite(seg.sMax) ||
        seg.sMin < 0.0 || seg.sMax > 1.0 || !(seg.sMax > seg.sMin)) {
        throw std::runtime_error(key + ": sMin/sMax must be finite relative coordinates with 0 <= sMin < sMax <= 1");
    }
    if (!std::isfinite(seg.ux) || !std::isfinite(seg.uy)) {
        throw std::runtime_error(key + ": ux/uy must be finite");
    }
    if (typeValue < 0 || typeValue > static_cast<long long>(std::numeric_limits<std::uint32_t>::max())) {
        throw std::runtime_error(key + ": type must be a non-negative uint32 value");
    }
    seg.type = static_cast<std::uint32_t>(typeValue);
    if (!std::isfinite(seg.mass) || !(seg.mass > 0.0)) {
        throw std::runtime_error(key + ": mass must be finite and positive");
    }
    return seg;
}

std::string boundary_mode_for_face(const SimulationParams& p, const std::string& face) {
    if (face == "left") return p.bcLeft;
    if (face == "right") return p.bcRight;
    if (face == "bottom") return p.bcBottom;
    if (face == "top") return p.bcTop;
    return "";
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
        const std::string lk = lower(trim(item.first));
        if (lk.rfind("q9", 0) == 0 || lk.rfind("virial", 0) == 0 ||
            lk == "kvirial" || lk == "betaeos" ||
            lk.rfind("massflux", 0) == 0 || lk.rfind("lowk", 0) == 0) {
            throw std::runtime_error("Unsupported parameter on openMP-resampling baseline: " + item.first +
                                     ". This branch intentionally supports only classic SRC/MPCD and Q6 projection.");
        }
    }

    for (const auto& item : kv) {
        const std::string& key = item.first;
        const std::string& value = item.second;

        if (key == "inputState") p.inputState = value;
        else if (key == "outputDir") p.outputDir = value;
        else if (key == "initialInactiveSlots") p.initialInactiveSlots = parse_u64(value, key);
        else if (key == "Lx") p.Lx = parse_double(value, key);
        else if (key == "Ly") p.Ly = parse_double(value, key);
        else if (key == "Nx") p.Nx = parse_int(value, key);
        else if (key == "Ny") p.Ny = parse_int(value, key);
        else if (key == "fluidXMin0") p.fluidXMin0 = parse_double(value, key);
        else if (key == "fluidXMax0") p.fluidXMax0 = parse_double(value, key);
        else if (key == "fluidYMin0") p.fluidYMin0 = parse_double(value, key);
        else if (key == "fluidYMax0" || key == "fluidYTop0") p.fluidYMax0 = parse_double(value, key);
        else if (key == "fluidXMinVelocity") p.fluidXMinVelocity = parse_double(value, key);
        else if (key == "fluidXMaxVelocity") p.fluidXMaxVelocity = parse_double(value, key);
        else if (key == "fluidYMinVelocity") p.fluidYMinVelocity = parse_double(value, key);
        else if (key == "fluidYMaxVelocity" || key == "fluidYTopVelocity") p.fluidYMaxVelocity = parse_double(value, key);
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
        else if (key == "taylorGreenForcingEnable" || key == "tgForcingEnable") p.taylorGreenForcingEnable = parse_bool(value, key);
        else if (key == "taylorGreenForcingAmplitude" || key == "tgForcingAmplitude" || key == "tgForceAmplitude") p.taylorGreenForcingAmplitude = parse_double(value, key);
        else if (key == "taylorGreenForcingModeX" || key == "tgForcingModeX") p.taylorGreenForcingModeX = parse_int(value, key);
        else if (key == "taylorGreenForcingModeY" || key == "tgForcingModeY") p.taylorGreenForcingModeY = parse_int(value, key);
        else if (key == "q6ForceProjectionMode") p.q6ForceProjectionMode = value;
        else if (key == "keepMeanFlowEnable" || key == "keepMeanFlow") p.keepMeanFlowEnable = parse_bool(value, key);
        else if (key == "targetMeanUx" || key == "meanFlowUx" || key == "U0") p.targetMeanUx = parse_double(value, key);
        else if (key == "targetMeanUy" || key == "meanFlowUy") p.targetMeanUy = parse_double(value, key);
        else if (key == "bcX" || key == "bcY" ||
                 key == "bcLeft" || key == "bcRight" ||
                 key == "bcBottom" || key == "bcTop" ||
                 key == "boundaryLeft" || key == "boundaryRight" ||
                 key == "boundaryBottom" || key == "boundaryTop") {
            // Applied after the generic loop so per-face keys override pair aliases.
        }
        else if (key == "inletUx" || key == "inletVelocityX") {
            const double u = parse_double(value, key);
            p.inletUxLeft = u;
            p.inletUxRight = u;
            p.inletUxBottom = u;
            p.inletUxTop = u;
        }
        else if (key == "inletUy" || key == "inletVelocityY") {
            const double u = parse_double(value, key);
            p.inletUyLeft = u;
            p.inletUyRight = u;
            p.inletUyBottom = u;
            p.inletUyTop = u;
        }
        else if (key == "inletUxLeft") p.inletUxLeft = parse_double(value, key);
        else if (key == "inletUyLeft") p.inletUyLeft = parse_double(value, key);
        else if (key == "inletUxRight") p.inletUxRight = parse_double(value, key);
        else if (key == "inletUyRight") p.inletUyRight = parse_double(value, key);
        else if (key == "inletUxBottom") p.inletUxBottom = parse_double(value, key);
        else if (key == "inletUyBottom") p.inletUyBottom = parse_double(value, key);
        else if (key == "inletUxTop") p.inletUxTop = parse_double(value, key);
        else if (key == "inletUyTop") p.inletUyTop = parse_double(value, key);
        else if (key == "inletVelocityRampEnable" || key == "inletRampEnable") p.inletVelocityRampEnable = parse_bool(value, key);
        else if (key == "inletVelocityRampStartTime" || key == "inletRampStartTime") p.inletVelocityRampStartTime = parse_double(value, key);
        else if (key == "inletVelocityRampEndTime" || key == "inletRampEndTime") p.inletVelocityRampEndTime = parse_double(value, key);
        else if (key == "inletVelocityRampInitialFactor" || key == "inletRampInitialFactor") p.inletVelocityRampInitialFactor = parse_double(value, key);
        else if (key == "inletVelocityRampFinalFactor" || key == "inletRampFinalFactor") p.inletVelocityRampFinalFactor = parse_double(value, key);
        else if (key == "inletVelocityRampProfile" || key == "inletRampProfile") p.inletVelocityRampProfile = get_lower(kv, key);
        else if (key == "inletVelocitySpatialProfile" || key == "inletSpatialProfile" ||
                 key == "inletProfile" || key == "openBoundaryVelocityProfile") {
            p.inletVelocitySpatialProfile = get_lower(kv, key);
            std::replace(p.inletVelocitySpatialProfile.begin(), p.inletVelocitySpatialProfile.end(), '-', '_');
        }
        else if (key == "inletVelocityWallTaperCells" || key == "inletWallTaperCells" ||
                 key == "openBoundaryVelocityWallTaperCells") {
            p.inletVelocityWallTaperCells = parse_double(value, key);
        }
        else if (key == "inletKBT") p.inletKBT = parse_double(value, key);
        else if (key == "inletThermalNoise") p.inletThermalNoise = parse_double(value, key);
        else if (key == "inletInjectionMode") p.inletInjectionMode = get_lower(kv, key);
        else if (key == "inletSlabCells" || key == "inletInjectionSlabCells") p.inletSlabCells = parse_double(value, key);
        else if (key == "inletRandomizeTangential" || key == "inletRandomizeTransverse" ||
                 key == "inletRandomizeY" || key == "injectRandomY") {
            p.inletRandomizeTangential = parse_bool(value, key);
        }
        else if (key == "inletReinjectBackflow" || key == "reinjectBackflow") p.inletReinjectBackflow = parse_bool(value, key);
        else if (key == "inletReservoirMode") p.inletReservoirMode = get_lower(kv, key);
        else if (key == "inletReservoirCells" || key == "inletDensityCells") p.inletReservoirCells = parse_int(value, key);
        else if (key == "inletTargetOccupancy" || key == "inletTargetN" || key == "inletGamma") p.inletTargetOccupancy = parse_int(value, key);
        else if (key == "inletHardCellVelocityMean") p.inletHardCellVelocityMean = parse_bool(value, key);
        else if (key == "inletHardCellThermalRescale") p.inletHardCellThermalRescale = parse_bool(value, key);
        else if (key == "openBoundarySegmentsEnable") p.openBoundarySegmentsEnable = parse_bool(value, key);
        else if (key == "openBoundarySegmentCount") p.openBoundarySegmentCount = parse_int(value, key);
        else if (is_open_boundary_segment_key(key)) {
            // Parsed after the generic loop, once openBoundarySegmentCount is known.
        }
        else if (is_removed_open_aperture_key(key)) {
            throw std::runtime_error("Parameter '" + key + "' was removed in 0143. Use compact relative segments: openBoundarySegmentsEnable=true, openBoundarySegmentCount=N, openBoundarySegmentK='face mode sMin sMax ux uy type mass'.");
        }
        else if (key == "openBoundaryOutletMode" || key == "openOutletBoundaryMode" ||
                 key == "outletBoundaryMode" || key == "q6q9OutletBoundaryMode") {
            p.openBoundaryOutletMode = get_lower(kv, key);
            std::replace(p.openBoundaryOutletMode.begin(), p.openBoundaryOutletMode.end(), '-', '_');
        }
        else if (key == "openBoundaryOutletHybridBlend" || key == "outletHybridBlend" ||
                 key == "openOutletHybridBlend") p.openBoundaryOutletHybridBlend = parse_double(value, key);
        else if (key == "openBoundaryOutletFeedbackGain" || key == "outletFeedbackGain" ||
                 key == "openOutletFeedbackGain" || key == "openBoundaryOutletMassFeedbackGain") p.openBoundaryOutletFeedbackGain = parse_double(value, key);
        else if (key == "openBoundaryOutletForcedMassFlux" || key == "outletForcedMassFlux" ||
                 key == "openOutletForcedMassFlux" || key == "outletSuctionMassFlux") p.openBoundaryOutletForcedMassFlux = parse_double(value, key);
        else if (key == "openBoundaryOutletForcedMassPerStep" || key == "outletForcedMassPerStep" ||
                 key == "openOutletForcedMassPerStep" || key == "outletSuctionMassPerStep") p.openBoundaryOutletForcedMassPerStep = parse_double(value, key);
        else if (key == "openBoundaryOutletForcedParticleFlux" || key == "outletForcedParticleFlux" ||
                 key == "openOutletForcedParticleFlux" || key == "outletSuctionParticleFlux") p.openBoundaryOutletForcedParticleFlux = parse_double(value, key);
        else if (key == "openBoundaryOutletForcedParticlesPerStep" || key == "outletForcedParticlesPerStep" ||
                 key == "openOutletForcedParticlesPerStep" || key == "outletSuctionParticlesPerStep") p.openBoundaryOutletForcedParticlesPerStep = parse_int(value, key);
        else if (key == "openBoundaryOutletForcedLayerCells" || key == "outletForcedLayerCells" ||
                 key == "openOutletForcedLayerCells" || key == "outletSuctionLayerCells") p.openBoundaryOutletForcedLayerCells = parse_int(value, key);
        else if (key == "wallVpEnable") p.wallVpEnable = parse_bool(value, key);
        else if (key == "wallVpMode") p.wallVpMode = get_lower(kv, key);
        else if (key == "wallAccommodation") p.wallAccommodation = parse_double(value, key);
        else if (key == "wallVpGamma") p.wallVpGamma = parse_double(value, key);
        else if (key == "wallVpMass") p.wallVpMass = parse_double(value, key);
        else if (key == "wallKBT") p.wallKBT = parse_double(value, key);
        else if (key == "wallVpKBT") p.wallVpKBT = parse_double(value, key);
        else if (key == "wallThermalNoise") p.wallThermalNoise = parse_double(value, key);
        else if (key == "wallVpUxLeft" || key == "wallUxLeft") p.wallVpUxLeft = parse_double(value, key);
        else if (key == "wallVpUyLeft" || key == "wallUyLeft") p.wallVpUyLeft = parse_double(value, key);
        else if (key == "wallVpUxRight" || key == "wallUxRight") p.wallVpUxRight = parse_double(value, key);
        else if (key == "wallVpUyRight" || key == "wallUyRight") p.wallVpUyRight = parse_double(value, key);
        else if (key == "wallVpUxBottom" || key == "wallUxBottom") p.wallVpUxBottom = parse_double(value, key);
        else if (key == "wallVpUyBottom" || key == "wallUyBottom") p.wallVpUyBottom = parse_double(value, key);
        else if (key == "wallVpUxTop" || key == "wallUxTop") p.wallVpUxTop = parse_double(value, key);
        else if (key == "wallVpUyTop" || key == "wallUyTop") p.wallVpUyTop = parse_double(value, key);
        else if (key == "immersedSolidEnable" || key == "immersedCircleEnable") {
            p.immersedSolidEnable = parse_bool(value, key);
            if (key == "immersedCircleEnable") p.immersedSolidShape = "circle";
        }
        else if (key == "immersedSolidShape") p.immersedSolidShape = get_lower(kv, key);
        else if (key == "immersedSolidCx" || key == "immersedCircleCx") p.immersedSolidCx = parse_double(value, key);
        else if (key == "immersedSolidCy" || key == "immersedCircleCy") p.immersedSolidCy = parse_double(value, key);
        else if (key == "immersedSolidR" || key == "immersedCircleR") p.immersedSolidR = parse_double(value, key);
        else if (key == "immersedSolidFractionSamples" || key == "immersedCircleFractionSamples") p.immersedSolidFractionSamples = parse_int(value, key);
        else if (key == "immersedSolidVx" || key == "immersedCircleVx") p.immersedSolidVx = parse_double(value, key);
        else if (key == "immersedSolidVy" || key == "immersedCircleVy") p.immersedSolidVy = parse_double(value, key);
        else if (key == "immersedSolidWallUx" || key == "immersedCircleWallUx") p.immersedSolidWallUx = parse_double(value, key);
        else if (key == "immersedSolidWallUy" || key == "immersedCircleWallUy") p.immersedSolidWallUy = parse_double(value, key);
        else if (key == "immersedSolidOmega" || key == "immersedCircleOmega") p.immersedSolidOmega = parse_double(value, key);
        else if (key == "immersedSolidXMin") p.immersedSolidXMin = parse_double(value, key);
        else if (key == "immersedSolidXMax") p.immersedSolidXMax = parse_double(value, key);
        else if (key == "immersedSolidYMin") p.immersedSolidYMin = parse_double(value, key);
        else if (key == "immersedSolidYMax") p.immersedSolidYMax = parse_double(value, key);
        else if (key == "thermostatEnable") p.thermostatEnable = parse_bool(value, key);
        else if (key == "thermostatMode") p.thermostatMode = get_lower(kv, key);
        else if (key == "thermostatEvery") p.thermostatEvery = parse_int(value, key);
        else if (key == "thermostatTargetKBT") p.thermostatTargetKBT = parse_double(value, key);
        else if (key == "thermostatMinParticles") p.thermostatMinParticles = parse_int(value, key);
        else if (key == "thermostatEpsilon") p.thermostatEpsilon = parse_double(value, key);
        else if (key == "kBT") p.kBT = parse_double(value, key);
        else if (key == "srcClassicCudaModeEnable" || key == "classicSrcCudaModeEnable" ||
                 key == "classicSrcModeEnable" || key == "classicSrcCudaMode") {
            p.srcClassicCudaModeEnable = parse_bool(value, key);
        }
        else if (key == "projectionEnable") p.projectionEnable = parse_bool(value, key);
        else if (key == "projectionOperator") p.projectionOperator = get_lower(kv, key);
        else if (key == "projectionBackend" || key == "q6ProjectionBackend" || key == "gpuProjectionBackend") {
            p.projectionBackend = get_lower(kv, key);
            std::replace(p.projectionBackend.begin(), p.projectionBackend.end(), '-', '_');
        }
        else if (key == "projectionMaxIterations") p.projectionMaxIterations = parse_int(value, key);
        else if (key == "projectionTolerance") p.projectionTolerance = parse_double(value, key);
        else if (key == "projectionMomentumCorrectionEnable") p.projectionMomentumCorrectionEnable = parse_bool(value, key);
        else if (key == "q6ProjectionStrength" || key == "projectionStrength") p.q6ProjectionStrength = parse_double(value, key);
        else if (key == "closedCapacityResponseEnable") p.closedCapacityResponseEnable = parse_bool(value, key);
        else if (key == "closedCapacityReferenceCellMass") p.closedCapacityReferenceCellMass = parse_double(value, key);
        else if (key == "closedCapacityReferenceParticleMass") p.closedCapacityReferenceParticleMass = parse_double(value, key);
        else if (key == "closedCapacityQ6Eta") p.closedCapacityQ6Eta = parse_double(value, key);
        else if (key == "closedCapacityQ6Power") p.closedCapacityQ6Power = parse_double(value, key);
        else if (key == "closedCapacityMassRemapEta") p.closedCapacityMassRemapEta = parse_double(value, key);
        else if (key == "closedCapacityMassRemapPower") p.closedCapacityMassRemapPower = parse_double(value, key);
        else if (key == "closedCapacityMassGuardDisableOnOverfill") p.closedCapacityMassGuardDisableOnOverfill = parse_bool(value, key);
        else if (key == "closedCapacityVirialKickEnable") p.closedCapacityVirialKickEnable = parse_bool(value, key);
        else if (key == "closedCapacityVirialBaseK") p.closedCapacityVirialBaseK = parse_double(value, key);
        else if (key == "closedCapacityVirialGain") p.closedCapacityVirialGain = parse_double(value, key);
        else if (key == "closedCapacityVirialEta") p.closedCapacityVirialEta = parse_double(value, key);
        else if (key == "closedCapacityVirialPower") p.closedCapacityVirialPower = parse_double(value, key);
        else if (key == "closedCapacityVirialKickStrength") p.closedCapacityVirialKickStrength = parse_double(value, key);
        else if (key == "closedCapacityVirialMomentumCorrectionEnable") p.closedCapacityVirialMomentumCorrectionEnable = parse_bool(value, key);
        else if (key == "closedCapacityInletMassFluxEnable") p.closedCapacityInletMassFluxEnable = parse_bool(value, key);
        else if (key == "closedCapacityInletMassFluxMultiplier") p.closedCapacityInletMassFluxMultiplier = parse_double(value, key);
        else if (key == "projectionImmersedSolidMaskEnable") p.projectionImmersedSolidMaskEnable = parse_bool(value, key);
        else if (key == "projectionAllowUnmaskedImmersedSolid") p.projectionAllowUnmaskedImmersedSolid = parse_bool(value, key);
        else if (key == "projectionImmersedSolidFluidFractionThreshold") p.projectionImmersedSolidFluidFractionThreshold = parse_double(value, key);
        else if (key == "projectionImmersedSolidCloseCutFaces") p.projectionImmersedSolidCloseCutFaces = parse_bool(value, key);
        else if (key == "resamplingTargetCellMass" || key == "weightedResamplingTargetCellMass") p.resamplingTargetCellMass = parse_double(value, key);
        else if (key == "resamplingWetMaskMode") {
            p.resamplingWetMaskMode = get_lower(kv, key);
            std::replace(p.resamplingWetMaskMode.begin(), p.resamplingWetMaskMode.end(), '-', '_');
        }
        else if (key == "resamplingWetCellMassThreshold" || key == "resamplingWetMassThreshold") p.resamplingWetCellMassThreshold = parse_double(value, key);
        else if (key == "resamplingPoorCellMassFraction" || key == "resamplingPoorMassFraction") p.resamplingPoorCellMassFraction = parse_double(value, key);
        else if (key == "resamplingRichCellMassFraction" || key == "resamplingRichMassFraction") p.resamplingRichCellMassFraction = parse_double(value, key);
        else if (key == "resamplingActiveFluidFractionThreshold") p.resamplingActiveFluidFractionThreshold = parse_double(value, key);
        else if (key == "resamplingEnable" || key == "weightedResamplingEnable") p.resamplingEnable = parse_bool(value, key);
        else if (key == "darcyBrinkmanEnable" || key == "topoDarcyEnable") p.darcyBrinkmanEnable = parse_bool(value, key);
        else if (key == "darcyChiMode") p.darcyChiMode = lower(trim(value));
        else if (key == "darcyUniformChi") p.darcyUniformChi = parse_double(value, key);
        else if (key == "darcyChiFile") p.darcyChiFile = value;
        else if (key == "darcyChiNx") p.darcyChiNx = parse_int(value, key);
        else if (key == "darcyChiNy") p.darcyChiNy = parse_int(value, key);
        else if (key == "darcyChiFileFormat") p.darcyChiFileFormat = lower(trim(value));
        else if (key == "darcyAlphaMin") p.darcyAlphaMin = parse_double(value, key);
        else if (key == "darcyAlphaMax") p.darcyAlphaMax = parse_double(value, key);
        else if (key == "darcyQ") p.darcyQ = parse_double(value, key);
        else if (key == "darcyUSolidX") p.darcyUSolidX = parse_double(value, key);
        else if (key == "darcyUSolidY") p.darcyUSolidY = parse_double(value, key);
        else if (key == "darcyCircleCx") p.darcyCircleCx = parse_double(value, key);
        else if (key == "darcyCircleCy") p.darcyCircleCy = parse_double(value, key);
        else if (key == "darcyCircleR") p.darcyCircleR = parse_double(value, key);
        else if (key == "darcyBoxXMin") p.darcyBoxXMin = parse_double(value, key);
        else if (key == "darcyBoxXMax") p.darcyBoxXMax = parse_double(value, key);
        else if (key == "darcyBoxYMin") p.darcyBoxYMin = parse_double(value, key);
        else if (key == "darcyBoxYMax") p.darcyBoxYMax = parse_double(value, key);
        else if (key == "darcyInterfaceWidth") p.darcyInterfaceWidth = parse_double(value, key);
        else if (key == "darcyCostEvery") p.darcyCostEvery = parse_int(value, key);
        else if (key == "darcyCostFilename") p.darcyCostFilename = value;
        else if (key == "darcyThreadsPerBlock") p.darcyThreadsPerBlock = parse_int(value, key);
        else if (key == "darcyInitialDeactivateBelowChi" || key == "darcyDeactivateInitialBelowChi") p.darcyInitialDeactivateBelowChi = parse_double(value, key);
        else if (key == "darcyBrinkmanForcingMode" || key == "darcyForcingMode") {
            p.darcyBrinkmanForcingMode = lower(trim(value));
            std::replace(p.darcyBrinkmanForcingMode.begin(), p.darcyBrinkmanForcingMode.end(), '-', '_');
        }
        else if (key == "darcyChiCollisionVpEnable" || key == "darcyCollisionVpEnable" || key == "topoChiCollisionVpEnable") p.darcyChiCollisionVpEnable = parse_bool(value, key);
        else if (key == "darcyChiCollisionVpMode" || key == "darcyCollisionVpMode" || key == "topoChiCollisionVpMode") {
            p.darcyChiCollisionVpMode = lower(trim(value));
            std::replace(p.darcyChiCollisionVpMode.begin(), p.darcyChiCollisionVpMode.end(), '-', '_');
        }
        else if (key == "darcyChiCollisionVpGamma" || key == "darcyCollisionVpGamma" || key == "topoChiCollisionVpGamma") p.darcyChiCollisionVpGamma = parse_double(value, key);
        else if (key == "darcyChiCollisionVpMass" || key == "darcyCollisionVpMass" || key == "topoChiCollisionVpMass") p.darcyChiCollisionVpMass = parse_double(value, key);
        else if (key == "darcyChiCollisionVpLayers" || key == "darcyCollisionVpLayers" || key == "topoChiCollisionVpLayers") p.darcyChiCollisionVpLayers = parse_int(value, key);
        else if (key == "darcyChiCollisionVpThreshold" || key == "darcyCollisionVpThreshold" || key == "topoChiCollisionVpThreshold") p.darcyChiCollisionVpThreshold = parse_double(value, key);
        else if (key == "darcyChiCollisionVpStrength" || key == "darcyCollisionVpStrength" || key == "topoChiCollisionVpStrength") p.darcyChiCollisionVpStrength = parse_double(value, key);
        else if (key == "topoBenchmarkEnable") p.topoBenchmarkEnable = parse_bool(value, key);
        else if (key == "topoBenchmarkEvery") p.topoBenchmarkEvery = parse_int(value, key);
        else if (key == "topoBenchmarkFilename") p.topoBenchmarkFilename = value;
        else if (key == "topoBenchmarkForceEnable") p.topoBenchmarkForceEnable = parse_bool(value, key);
        else if (key == "topoBenchmarkDragLiftEnable") p.topoBenchmarkDragLiftEnable = parse_bool(value, key);
        else if (key == "topoBenchmarkFlowDirX") p.topoBenchmarkFlowDirX = parse_double(value, key);
        else if (key == "topoBenchmarkFlowDirY") p.topoBenchmarkFlowDirY = parse_double(value, key);
        else if (key == "topoBenchmarkLiftDirX") p.topoBenchmarkLiftDirX = parse_double(value, key);
        else if (key == "topoBenchmarkLiftDirY") p.topoBenchmarkLiftDirY = parse_double(value, key);
        else if (key == "resamplingExtractionEnable") p.resamplingExtractionEnable = parse_bool(value, key);
        else if (key == "resamplingInsertionEnable") p.resamplingInsertionEnable = parse_bool(value, key);
        else if (key == "resamplingRemapEnable") p.resamplingRemapEnable = parse_bool(value, key);
        else if (key == "resamplingThermalRenormalizationEnable" || key == "resamplingThermalRenormalisationEnable") p.resamplingThermalRenormalizationEnable = parse_bool(value, key);
        else if (key == "resamplingMassRenormalizationPeriod" || key == "resamplingMassRenormalisationPeriod" ||
                 key == "resamplingRemapPeriod" || key == "resamplingMassRemapPeriod") {
            p.resamplingMassRenormalizationPeriod = parse_int(value, key);
        }
        else if (key == "resamplingMassGuardEnable" || key == "resamplingMassSafetyEnable") p.resamplingMassGuardEnable = parse_bool(value, key);
        else if (key == "resamplingParticleMassMin" || key == "resamplingMassMin") p.resamplingParticleMassMin = parse_double(value, key);
        else if (key == "resamplingParticleMassMax" || key == "resamplingMassMax") p.resamplingParticleMassMax = parse_double(value, key);
        else if (key == "resamplingLatentActivationEnable" || key == "resamplingLatentToFluidEnable") p.resamplingLatentActivationEnable = parse_bool(value, key);
        else if (key == "resamplingLatentActivationMaxPerCell") p.resamplingLatentActivationMaxPerCell = parse_int(value, key);
        else if (key == "resamplingLatentActivationParticleMass" || key == "resamplingLatentParticleMass") p.resamplingLatentActivationParticleMass = parse_double(value, key);
        else if (key == "resamplingPopulationNMin" || key == "resamplingNMin") p.resamplingPopulationNMin = parse_int(value, key);
        else if (key == "resamplingPopulationNTarget" || key == "resamplingNTarget") p.resamplingPopulationNTarget = parse_int(value, key);
        else if (key == "resamplingPopulationNMax" || key == "resamplingNMax") p.resamplingPopulationNMax = parse_int(value, key);
        else if (key == "resamplingPopulationNMinFraction" || key == "resamplingNMinFraction") p.resamplingPopulationNMinFraction = parse_double(value, key);
        else if (key == "resamplingPopulationNMaxFraction" || key == "resamplingNMaxFraction") p.resamplingPopulationNMaxFraction = parse_double(value, key);
        else if (key == "resamplingPopulationMaxSplitsPerCell" || key == "resamplingNMaxSplitsPerCell") p.resamplingPopulationMaxSplitsPerCell = parse_int(value, key);
        else if (key == "resamplingPopulationMaxSplitsPerStep" || key == "resamplingNMaxSplitsPerStep") p.resamplingPopulationMaxSplitsPerStep = parse_int(value, key);
        else if (key == "resamplingPopulationMaxExtractionsPerCell" || key == "resamplingNMaxExtractionsPerCell") p.resamplingPopulationMaxExtractionsPerCell = parse_int(value, key);
        else if (key == "resamplingPopulationMaxExtractionsPerStep" || key == "resamplingNMaxExtractionsPerStep") p.resamplingPopulationMaxExtractionsPerStep = parse_int(value, key);
        else if (key == "cudaResamplingEmptyRefillEnable") p.cudaResamplingEmptyRefillEnable = parse_bool(value, key);
        else if (key == "cudaResamplingEmptyRefillTargetFraction") p.cudaResamplingEmptyRefillTargetFraction = parse_double(value, key);
        else if (key == "cudaResamplingEmptyRefillReference") {
            p.cudaResamplingEmptyRefillReference = get_lower(kv, key);
            std::replace(p.cudaResamplingEmptyRefillReference.begin(), p.cudaResamplingEmptyRefillReference.end(), '-', '_');
        }
        else if (key == "cudaResamplingEmptyRefillGamma") p.cudaResamplingEmptyRefillGamma = parse_int(value, key);
        else if (key == "cudaResamplingEmptyRefillMemoryMaxAge") p.cudaResamplingEmptyRefillMemoryMaxAge = parse_int(value, key);
        else if (key == "cudaResamplingChiFilterEnable" || key == "cudaResamplingDarcyChiFilterEnable") p.cudaResamplingChiFilterEnable = parse_bool(value, key);
        else if (key == "cudaResamplingChiMin" || key == "cudaResamplingDarcyChiMin") p.cudaResamplingChiMin = parse_double(value, key);
        else if (key == "speciesRegistryEnable") p.speciesRegistryEnable = parse_bool(value, key);
        else if (key == "speciesCount") p.speciesCount = parse_int(value, key);
        else if (key == "speciesRequireRegisteredTypes") p.speciesRequireRegisteredTypes = parse_bool(value, key);
        else if (key == "speciesDiagnosticsEnable") p.speciesDiagnosticsEnable = parse_bool(value, key);
        else if (key == "speciesDiagnosticsFilename") p.speciesDiagnosticsFilename = trim(value);
        else if (key == "speciesCellDiagnosticsEnable") p.speciesCellDiagnosticsEnable = parse_bool(value, key);
        else if (key == "speciesCellDiagnosticsFilename") p.speciesCellDiagnosticsFilename = trim(value);
        else if (key == "speciesCellCudaDepositEnable") p.speciesCellCudaDepositEnable = parse_bool(value, key);
        else if (key == "speciesCellCudaComparisonFilename") p.speciesCellCudaComparisonFilename = trim(value);
        else if (key == "speciesCellCudaComparisonTolerance") p.speciesCellCudaComparisonTolerance = parse_double(value, key);
        else if (key == "speciesCellCudaThreadsPerBlock") p.speciesCellCudaThreadsPerBlock = parse_int(value, key);
        else if (key == "speciesQ6Enable") p.speciesQ6Enable = parse_bool(value, key);
        else if (key == "speciesQ6Mode") {
            p.speciesQ6Mode = get_lower(kv, key);
            std::replace(p.speciesQ6Mode.begin(), p.speciesQ6Mode.end(), '-', '_');
        }
        else if (key == "speciesQ6Sensitivity") p.speciesQ6Sensitivity = parse_double(value, key);
        else if (key == "speciesQ6AlphaEpsilon") p.speciesQ6AlphaEpsilon = parse_double(value, key);
        else if (key == "speciesQ6FallbackMode") {
            p.speciesQ6FallbackMode = get_lower(kv, key);
            std::replace(p.speciesQ6FallbackMode.begin(), p.speciesQ6FallbackMode.end(), '-', '_');
        }
        else if (key == "speciesQ6ComparisonTolerance") p.speciesQ6ComparisonTolerance = parse_double(value, key);
        else if (key == "speciesQ6MinOccupancyFraction") p.speciesQ6MinOccupancyFraction = parse_double(value, key);
        else if (key == "speciesResamplingMassClosureEnable") p.speciesResamplingMassClosureEnable = parse_bool(value, key);
        else if (key == "speciesResamplingMassClosureCudaEnable") p.speciesResamplingMassClosureCudaEnable = parse_bool(value, key);
        else if (key == "speciesMassClosureCudaDiagnosticsFilename") p.speciesMassClosureCudaDiagnosticsFilename = trim(value);
        else if (key == "speciesMassClosureCudaComparisonTolerance") p.speciesMassClosureCudaComparisonTolerance = parse_double(value, key);
        else if (key == "speciesResamplingPopulationGuardEnable") p.speciesResamplingPopulationGuardEnable = parse_bool(value, key);
        else if (key == "speciesResamplingPopulationGuardCudaEnable") p.speciesResamplingPopulationGuardCudaEnable = parse_bool(value, key);
        else if (key == "speciesResamplingTransferEnable") p.speciesResamplingTransferEnable = parse_bool(value, key);
        else if (key == "speciesResamplingTransferCudaEnable") p.speciesResamplingTransferCudaEnable = parse_bool(value, key);
        else if (key == "speciesTransferCudaDiagnosticsFilename") p.speciesTransferCudaDiagnosticsFilename = trim(value);
        else if (key == "speciesTransferCudaComparisonTolerance") p.speciesTransferCudaComparisonTolerance = parse_double(value, key);
        else if (key == "speciesResamplingCudaResidentValidationEnable") p.speciesResamplingCudaResidentValidationEnable = parse_bool(value, key);
        else if (key == "speciesResamplingCudaResidentFastPathEnable") p.speciesResamplingCudaResidentFastPathEnable = parse_bool(value, key);
        else if (key == "speciesCudaResidentFastPathDiagnosticsFilename") p.speciesCudaResidentFastPathDiagnosticsFilename = trim(value);
        else if (key == "speciesResamplingCudaResidentDepositsEnable") p.speciesResamplingCudaResidentDepositsEnable = parse_bool(value, key);
        else if (key == "speciesResamplingCudaResidentPoolEnable") p.speciesResamplingCudaResidentPoolEnable = parse_bool(value, key);
        else if (key == "speciesResamplingCudaResidentMaintenanceStrict") p.speciesResamplingCudaResidentMaintenanceStrict = parse_bool(value, key);
        else if (key == "speciesCudaResidentMaintenanceDiagnosticsFilename") p.speciesCudaResidentMaintenanceDiagnosticsFilename = trim(value);
        else if (key == "cudaResamplingEmptyRefillSpeciesCompositionEnable") p.cudaResamplingEmptyRefillSpeciesCompositionEnable = parse_bool(value, key);
        else if (parse_species_resampling_enable_key(key, nullptr)) {
            // Parsed after the generic loop, once speciesCount and speciesK are known.
        }
        else if (is_species_definition_key(key)) {
            // Parsed after the generic loop, once speciesCount is known.
        }
        else if (key == "summaryEvery") p.summaryEvery = parse_int(value, key);
        else if (key == "dumpStateEvery") p.dumpStateEvery = parse_int(value, key);
        else if (key == "dumpRoleFilter" || key == "dumpParticleRoleFilter") p.dumpRoleFilter = get_lower(kv, key);
        else if (key == "summaryRoleFilter" || key == "summaryParticleRoleFilter") p.summaryRoleFilter = get_lower(kv, key);
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

    p.openBoundarySegments.clear();
    if (p.openBoundarySegmentsEnable) {
        if (p.openBoundarySegmentCount <= 0) {
            throw std::runtime_error("openBoundarySegmentsEnable=true requires openBoundarySegmentCount>0");
        }
        if (p.openBoundarySegmentCount > kOpenBoundaryMaxSegments) {
            throw std::runtime_error("openBoundarySegmentCount exceeds the 0143 safety limit of " + std::to_string(kOpenBoundaryMaxSegments));
        }
        p.openBoundarySegments.reserve(static_cast<std::size_t>(p.openBoundarySegmentCount));
        for (int k = 0; k < p.openBoundarySegmentCount; ++k) {
            const std::string segKey = "openBoundarySegment" + std::to_string(k);
            if (!has_key(kv, segKey)) {
                throw std::runtime_error("Missing required segmented boundary entry: " + segKey);
            }
            p.openBoundarySegments.push_back(parse_open_boundary_segment_value(kv.at(segKey), segKey));
        }
    } else {
        if (p.openBoundarySegmentCount != 0) {
            throw std::runtime_error("openBoundarySegmentCount is set but openBoundarySegmentsEnable=false; enable segments explicitly or remove the segment keys");
        }
        for (const auto& item : kv) {
            if (is_open_boundary_segment_key(item.first)) {
                throw std::runtime_error("Found " + item.first + " but openBoundarySegmentsEnable=false; enable segments explicitly");
            }
        }
    }

    p.speciesDefinitions.clear();
    if (p.speciesRegistryEnable) {
        if (p.speciesCount <= 0) {
            throw std::runtime_error("speciesRegistryEnable=true requires speciesCount>0");
        }
        int speciesDeclarationKeyCount = 0;
        for (const auto& item : kv) {
            if (is_species_definition_key(item.first)) ++speciesDeclarationKeyCount;
        }
        if (speciesDeclarationKeyCount != p.speciesCount) {
            throw std::runtime_error(
                "speciesCount=" + std::to_string(p.speciesCount) +
                " but found " + std::to_string(speciesDeclarationKeyCount) +
                " speciesK declarations");
        }
        p.speciesDefinitions.reserve(static_cast<std::size_t>(p.speciesCount));
        for (int k = 0; k < p.speciesCount; ++k) {
            const std::string speciesKey = "species" + std::to_string(k);
            if (!has_key(kv, speciesKey)) {
                throw std::runtime_error("Missing required species declaration: " + speciesKey);
            }
            SpeciesDefinition definition =
                parse_species_definition_value(kv.at(speciesKey), speciesKey);
            const std::string resamplingKey =
                speciesKey + "ResamplingEnable";
            if (has_key(kv, resamplingKey)) {
                definition.resamplingEnable = parse_bool(kv.at(resamplingKey), resamplingKey);
            }
            p.speciesDefinitions.push_back(std::move(definition));
        }
        for (const auto& item : kv) {
            int speciesIndex = -1;
            if (parse_species_resampling_enable_key(item.first, &speciesIndex) &&
                (speciesIndex < 0 || speciesIndex >= p.speciesCount)) {
                throw std::runtime_error(
                    item.first + ": species index is outside [0,speciesCount)");
            }
        }
        validate_species_definitions(p.speciesDefinitions, "simulation species registry");
    } else {
        if (p.speciesCount != 0) {
            throw std::runtime_error(
                "speciesCount is set but speciesRegistryEnable=false; enable the registry or remove species declarations");
        }
        for (const auto& item : kv) {
            if (is_species_definition_key(item.first) ||
                parse_species_resampling_enable_key(item.first, nullptr)) {
                throw std::runtime_error("Found " + item.first +
                                         " but speciesRegistryEnable=false");
            }
        }
        if (p.speciesRequireRegisteredTypes) {
            throw std::runtime_error(
                "speciesRequireRegisteredTypes=true requires speciesRegistryEnable=true");
        }
    }

    if (has_key(kv, "immersedCircleEnable") && !has_key(kv, "immersedSolidShape")) {
        p.immersedSolidShape = "circle";
    }
    if (has_key(kv, "immersedSolidShape")) {
        p.immersedSolidShape = get_lower(kv, "immersedSolidShape");
    }

    validate_simulation_params(p);
    return p;
}

bool is_x_periodic(const SimulationParams& p) {
    return p.bcLeft == "periodic" && p.bcRight == "periodic";
}

bool is_y_periodic(const SimulationParams& p) {
    return p.bcBottom == "periodic" && p.bcTop == "periodic";
}

bool is_solid_wall_mode(const std::string& mode) {
    return mode == "solid" || mode == "specular" || mode == "bounceback";
}

bool is_inlet_boundary_mode(const std::string& mode) {
    return mode == "inlet" || mode == "input";
}

bool is_outlet_boundary_mode(const std::string& mode) {
    return mode == "outlet" || mode == "output" || mode == "open";
}

bool is_io_boundary_mode(const std::string& mode) {
    return is_inlet_boundary_mode(mode) || is_outlet_boundary_mode(mode);
}

bool has_solid_wall(const SimulationParams& p) {
    return is_solid_wall_mode(p.bcLeft) || is_solid_wall_mode(p.bcRight) ||
           is_solid_wall_mode(p.bcBottom) || is_solid_wall_mode(p.bcTop);
}

bool has_io_boundary(const SimulationParams& p) {
    return is_io_boundary_mode(p.bcLeft) || is_io_boundary_mode(p.bcRight) ||
           is_io_boundary_mode(p.bcBottom) || is_io_boundary_mode(p.bcTop) ||
           has_open_boundary_segments(p);
}

std::string normalized_inlet_reservoir_mode(const SimulationParams& p) {
    std::string mode = p.inletReservoirMode;
    std::replace(mode.begin(), mode.end(), '-', '_');
    if (mode.empty() || mode == "default") {
        mode = p.inletInjectionMode;
        std::replace(mode.begin(), mode.end(), '-', '_');
    }
    if (mode == "cuda_recycle" || mode == "thin_slab") return "recycle";
    return mode;
}

bool hard_inlet_reservoir_requested(const SimulationParams& p) {
    const std::string mode = normalized_inlet_reservoir_mode(p);
    return mode == "hard_cell_density" || mode == "hard_density" || mode == "hard" || mode == "cell_density";
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
    const double xMax0 = p.fluidXMax0 >= 0.0 ? p.fluidXMax0 : p.Lx;
    const double yMax0 = p.fluidYMax0 >= 0.0 ? p.fluidYMax0 : p.Ly;
    if (p.fluidXMin0 < 0.0 || p.fluidYMin0 < 0.0 || xMax0 > p.Lx || yMax0 > p.Ly ||
        !(xMax0 > p.fluidXMin0) || !(yMax0 > p.fluidYMin0)) {
        throw std::runtime_error("Initial active fluid domain must lie inside [0,Lx]x[0,Ly] with positive area");
    }
    if ((p.bcLeft == "periodic" || p.bcRight == "periodic") &&
        (std::abs(p.fluidXMin0) > 1.0e-14 || std::abs(xMax0 - p.Lx) > 1.0e-14 ||
         std::abs(p.fluidXMinVelocity) > 0.0 || std::abs(p.fluidXMaxVelocity) > 0.0)) {
        throw std::runtime_error("Periodic x boundaries require a full, static active fluid x-domain");
    }
    if ((p.bcBottom == "periodic" || p.bcTop == "periodic") &&
        (std::abs(p.fluidYMin0) > 1.0e-14 || std::abs(yMax0 - p.Ly) > 1.0e-14 ||
         std::abs(p.fluidYMinVelocity) > 0.0 || std::abs(p.fluidYMaxVelocity) > 0.0)) {
        throw std::runtime_error("Periodic y boundaries require a full, static active fluid y-domain");
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

    const bool xWallPair = !leftPeriodic && is_wall_mode(p.bcLeft) && is_wall_mode(p.bcRight);
    const bool yWallPair = !bottomPeriodic && is_wall_mode(p.bcBottom) && is_wall_mode(p.bcTop);
    const bool xIoPair = !leftPeriodic &&
        ((is_inlet_boundary_mode(p.bcLeft) && is_outlet_boundary_mode(p.bcRight)) ||
         (is_outlet_boundary_mode(p.bcLeft) && is_inlet_boundary_mode(p.bcRight)));
    const bool yIoPair = !bottomPeriodic &&
        ((is_inlet_boundary_mode(p.bcBottom) && is_outlet_boundary_mode(p.bcTop)) ||
         (is_outlet_boundary_mode(p.bcBottom) && is_inlet_boundary_mode(p.bcTop)));
    const bool xHasIO = !leftPeriodic &&
        (is_io_boundary_mode(p.bcLeft) || is_io_boundary_mode(p.bcRight) ||
         has_open_boundary_segments_on_x_axis(p));
    const bool yHasIO = !bottomPeriodic &&
        (is_io_boundary_mode(p.bcBottom) || is_io_boundary_mode(p.bcTop) ||
         has_open_boundary_segments_on_y_axis(p));
    const bool xBoundaryModesSupported = !leftPeriodic &&
        (is_wall_mode(p.bcLeft) || is_io_boundary_mode(p.bcLeft)) &&
        (is_wall_mode(p.bcRight) || is_io_boundary_mode(p.bcRight));
    const bool yBoundaryModesSupported = !bottomPeriodic &&
        (is_wall_mode(p.bcBottom) || is_io_boundary_mode(p.bcBottom)) &&
        (is_wall_mode(p.bcTop) || is_io_boundary_mode(p.bcTop));

    if (!leftPeriodic && !xWallPair && !xIoPair && !xBoundaryModesSupported) {
        throw std::runtime_error("Non-periodic x boundaries require wall/inlet/outlet modes on both faces");
    }
    if (!bottomPeriodic && !yWallPair && !yIoPair && !yBoundaryModesSupported) {
        throw std::runtime_error("Non-periodic y boundaries require wall/inlet/outlet modes on both faces");
    }

    const bool hasIO = xHasIO || yHasIO || has_io_boundary(p);
    if (hasIO) {
        if (xHasIO && yHasIO) {
            throw std::runtime_error("0142 standalone/open-boundary support keeps one open axis at a time");
        }
        const bool standaloneOpenBoundary = (xHasIO && (!xIoPair || has_open_boundary_segments_on_x_axis(p))) ||
                                            (yHasIO && (!yIoPair || has_open_boundary_segments_on_y_axis(p)));
        const bool q6OpenBoundary = p.projectionEnable;
        const bool hardInletReservoir = hard_inlet_reservoir_requested(p);
        if (standaloneOpenBoundary && !hardInletReservoir) {
            throw std::runtime_error("0142 standalone inlet/outlet with a solid opposite face requires inletReservoirMode=hard_cell_density so particle roles can deactivate exits and activate the inlet reservoir");
        }
        if (q6OpenBoundary && p.immersedSolidEnable) {
            std::string solidShapeForOpen = p.immersedSolidShape;
            std::replace(solidShapeForOpen.begin(), solidShapeForOpen.end(), '-', '_');
            const bool staticRectangle =
                (solidShapeForOpen == "rectangle" || solidShapeForOpen == "rect" ||
                 solidShapeForOpen == "box" || solidShapeForOpen == "step") &&
                std::abs(p.immersedSolidVx) == 0.0 &&
                std::abs(p.immersedSolidVy) == 0.0 &&
                std::abs(p.immersedSolidOmega) == 0.0;
            if (!hardInletReservoir || !staticRectangle || !p.projectionImmersedSolidMaskEnable ||
                p.projectionAllowUnmaskedImmersedSolid) {
                throw std::runtime_error("0067 Q6 inlet/outlet with immersed solids requires hard_cell_density inlet, fixed rectangle, projectionImmersedSolidMaskEnable=true and projectionAllowUnmaskedImmersedSolid=false");
            }
        }
        std::string inletInjectionMode = p.inletInjectionMode;
        std::replace(inletInjectionMode.begin(), inletInjectionMode.end(), '-', '_');
        if (inletInjectionMode != "cuda_recycle" && inletInjectionMode != "thin_slab" &&
            inletInjectionMode != "hard_cell_density" && inletInjectionMode != "hard_density" &&
            inletInjectionMode != "hard" && inletInjectionMode != "cell_density") {
            throw std::runtime_error("inletInjectionMode currently supports cuda_recycle/thin_slab/hard_cell_density");
        }
        const std::string inletReservoirMode = normalized_inlet_reservoir_mode(p);
        if (inletReservoirMode != "recycle" && inletReservoirMode != "hard_cell_density" &&
            inletReservoirMode != "hard_density" && inletReservoirMode != "hard" &&
            inletReservoirMode != "cell_density") {
            throw std::runtime_error("inletReservoirMode supports recycle or hard_cell_density");
        }
        if (hardInletReservoir) {
            if (p.inletReservoirCells <= 0) {
                throw std::runtime_error("hard_cell_density inlet requires inletReservoirCells>0");
            }
            if (p.inletTargetOccupancy <= 0) {
                throw std::runtime_error("hard_cell_density inlet requires inletTargetOccupancy>0");
            }
        }
        if (!(p.inletThermalNoise >= 0.0) || !std::isfinite(p.inletThermalNoise)) {
            throw std::runtime_error("inletThermalNoise must be finite and non-negative");
        }
        if (!(p.inletSlabCells > 0.0) || !std::isfinite(p.inletSlabCells)) {
            throw std::runtime_error("inletSlabCells must be finite and positive");
        }
        if (p.inletThermalNoise > 0.0) {
            const double effectiveInletKBT = p.inletKBT > 0.0 ? p.inletKBT : p.kBT;
            if (!(effectiveInletKBT > 0.0)) {
                throw std::runtime_error("inletKBT is negative, so kBT must be positive when inletThermalNoise>0");
            }
        }
        double inletSpeedScale = std::max({
            std::abs(p.inletUxLeft), std::abs(p.inletUyLeft),
            std::abs(p.inletUxRight), std::abs(p.inletUyRight),
            std::abs(p.inletUxBottom), std::abs(p.inletUyBottom),
            std::abs(p.inletUxTop), std::abs(p.inletUyTop)});
        for (const auto& seg : p.openBoundarySegments) {
            if (open_boundary_segment_is_inlet(seg)) {
                inletSpeedScale = std::max(inletSpeedScale, std::max(std::abs(seg.ux), std::abs(seg.uy)));
            }
        }
        if (!std::isfinite(inletSpeedScale)) {
            throw std::runtime_error("Inlet velocities must be finite");
        }
        {
            std::string spatialProfile = p.inletVelocitySpatialProfile;
            std::replace(spatialProfile.begin(), spatialProfile.end(), '-', '_');
            if (spatialProfile != "uniform" &&
                spatialProfile != "poiseuille_y" &&
                spatialProfile != "poiseuille_y_mean" &&
                spatialProfile != "poiseuille_y_max" &&
                spatialProfile != "flat_taper_y" &&
                spatialProfile != "flat_taper_y_mean") {
                throw std::runtime_error("inletVelocitySpatialProfile must be uniform, poiseuille_y, poiseuille_y_mean, poiseuille_y_max, flat_taper_y, or flat_taper_y_mean");
            }
            if (!std::isfinite(p.inletVelocityWallTaperCells) || p.inletVelocityWallTaperCells < 0.0) {
                throw std::runtime_error("inletVelocityWallTaperCells must be finite and non-negative");
            }
        }

        if (p.inletVelocityRampEnable) {
            if (!std::isfinite(p.inletVelocityRampStartTime) ||
                !std::isfinite(p.inletVelocityRampEndTime) ||
                !std::isfinite(p.inletVelocityRampInitialFactor) ||
                !std::isfinite(p.inletVelocityRampFinalFactor)) {
                throw std::runtime_error("inlet velocity ramp parameters must be finite");
            }
            if (p.inletVelocityRampEndTime < p.inletVelocityRampStartTime) {
                throw std::runtime_error("inletVelocityRampEndTime must be >= inletVelocityRampStartTime");
            }
            if (p.inletVelocityRampProfile != "linear" &&
                p.inletVelocityRampProfile != "smoothstep") {
                throw std::runtime_error("inletVelocityRampProfile must be linear or smoothstep");
            }
        }
        {
            std::string outletMode = lower(trim(p.openBoundaryOutletMode));
            std::replace(outletMode.begin(), outletMode.end(), '-', '_');
            if (outletMode != "balanced_flux" && outletMode != "prescribed_flux" &&
                outletMode != "balanced" && outletMode != "prescribed" &&
                outletMode != "dirichlet" && outletMode != "neumann" &&
                outletMode != "free" && outletMode != "zero_gradient" &&
                outletMode != "zero_normal_gradient" && outletMode != "hybrid" &&
                outletMode != "neumann_feedback" && outletMode != "hybrid_feedback" &&
                outletMode != "equilibrium_flux" && outletMode != "equilibrium" &&
                outletMode != "balanced_particle_flux" && outletMode != "forced_flux" &&
                outletMode != "forced_mass_flux" && outletMode != "suction" &&
                outletMode != "forced") {
                throw std::runtime_error("openBoundaryOutletMode must be neumann, equilibrium_flux, forced_flux, balanced_flux, or hybrid");
            }
            if (p.openBoundaryOutletHybridBlend < 0.0 || p.openBoundaryOutletHybridBlend > 1.0) {
                throw std::runtime_error("openBoundaryOutletHybridBlend must be in [0,1]");
            }
            if (p.openBoundaryOutletFeedbackGain < 0.0 || p.openBoundaryOutletFeedbackGain > 1.0) {
                throw std::runtime_error("openBoundaryOutletFeedbackGain must be in [0,1]");
            }
            if (p.openBoundaryOutletForcedMassFlux < 0.0 || p.openBoundaryOutletForcedMassPerStep < 0.0 ||
                p.openBoundaryOutletForcedParticleFlux < 0.0 || p.openBoundaryOutletForcedParticlesPerStep < 0) {
                throw std::runtime_error("forced outlet flux parameters must be non-negative");
            }
            if (p.openBoundaryOutletForcedLayerCells < 1) {
                throw std::runtime_error("openBoundaryOutletForcedLayerCells must be >= 1");
            }
            if ((outletMode == "forced_flux" || outletMode == "forced_mass_flux" ||
                 outletMode == "suction" || outletMode == "forced") &&
                p.openBoundaryOutletForcedMassFlux <= 0.0 && p.openBoundaryOutletForcedMassPerStep <= 0.0 &&
                p.openBoundaryOutletForcedParticleFlux <= 0.0 && p.openBoundaryOutletForcedParticlesPerStep <= 0) {
                throw std::runtime_error("openBoundaryOutletMode=forced_flux requires a positive forced mass or particle flux");
            }
        }
        if (p.openBoundarySegmentsEnable) {
            if (p.openBoundarySegments.size() != static_cast<std::size_t>(p.openBoundarySegmentCount)) {
                throw std::runtime_error("openBoundarySegmentCount does not match parsed openBoundarySegments size");
            }
            std::string segmentOutletMode = lower(trim(p.openBoundaryOutletMode));
            std::replace(segmentOutletMode.begin(), segmentOutletMode.end(), '-', '_');
            if (has_outlet_open_boundary_segment(p)) {
                const bool outletModeOk = segmentOutletMode == "neumann" || segmentOutletMode == "free" ||
                    segmentOutletMode == "zero_gradient" || segmentOutletMode == "zero_normal_gradient" ||
                    segmentOutletMode == "hybrid" || segmentOutletMode == "neumann_feedback" || segmentOutletMode == "hybrid_feedback" ||
                    segmentOutletMode == "equilibrium_flux" || segmentOutletMode == "equilibrium" ||
                    segmentOutletMode == "balanced_particle_flux" || segmentOutletMode == "forced_flux" ||
                    segmentOutletMode == "forced_mass_flux" || segmentOutletMode == "suction" || segmentOutletMode == "forced";
                if (!outletModeOk) {
                    throw std::runtime_error("0143 segmented outlets require openBoundaryOutletMode=neumann, hybrid, equilibrium_flux, or forced_flux; balanced_flux is ambiguous for same-face/multiple outlets");
                }
                if ((segmentOutletMode == "hybrid" || segmentOutletMode == "neumann_feedback" || segmentOutletMode == "hybrid_feedback") &&
                    p.openBoundaryOutletHybridBlend != 0.0) {
                    throw std::runtime_error("0143 segmented hybrid outlets support feedback only; set openBoundaryOutletHybridBlend=0");
                }
            }
            for (const auto& seg : p.openBoundarySegments) {
                const std::string faceMode = boundary_mode_for_face(p, seg.face);
                if (faceMode == "periodic") {
                    throw std::runtime_error("openBoundarySegment on face '" + seg.face + "' is incompatible with a periodic boundary face");
                }
                if (is_io_boundary_mode(faceMode)) {
                    throw std::runtime_error("openBoundarySegment on face '" + seg.face + "' must be used with bcFace=solid/specular/bounceback, not a full-face inlet/outlet");
                }
                if (!is_wall_mode(faceMode)) {
                    throw std::runtime_error("openBoundarySegment on face '" + seg.face + "' requires a wall-like bcFace mode");
                }
            }
            const char* faces[] = {"left", "right", "bottom", "top"};
            for (const char* face : faces) {
                std::vector<OpenBoundarySegment> local;
                for (const auto& seg : p.openBoundarySegments) {
                    if (seg.face == face) local.push_back(seg);
                }
                std::sort(local.begin(), local.end(), [](const OpenBoundarySegment& a, const OpenBoundarySegment& b) {
                    return a.sMin < b.sMin;
                });
                for (std::size_t i = 1; i < local.size(); ++i) {
                    if (local[i].sMin < local[i - 1].sMax) {
                        throw std::runtime_error("openBoundarySegment intervals overlap on face '" + std::string(face) + "'");
                    }
                }
            }
        }
    }

    if (p.keepMeanFlowEnable) {
        if (!std::isfinite(p.targetMeanUx) || !std::isfinite(p.targetMeanUy)) {
            throw std::runtime_error("targetMeanUx/targetMeanUy must be finite when keepMeanFlowEnable=true");
        }
    }

    if (p.wallVpMode != "thermal" &&
        p.wallVpMode != "deterministic_thermal" &&
        p.wallVpMode != "stochastic_fraction") {
        throw std::runtime_error("wallVpMode supports thermal/deterministic_thermal; stochastic_fraction is accepted as a legacy alias");
    }
    if (!(p.wallAccommodation >= 0.0 && p.wallAccommodation <= 1.0)) {
        throw std::runtime_error("wallAccommodation must lie in [0,1]");
    }
    if (!(p.wallVpGamma >= 0.0)) {
        throw std::runtime_error("wallVpGamma must be non-negative; use 0 to infer the mean real occupancy");
    }
    if (!(p.wallVpMass > 0.0)) {
        throw std::runtime_error("wallVpMass must be positive");
    }
    if (!(p.wallThermalNoise >= 0.0)) {
        throw std::runtime_error("wallThermalNoise must be non-negative");
    }
    if ((has_solid_wall(p) || p.wallVpEnable || p.immersedSolidEnable) && p.wallAccommodation > 0.0) {
        const double effectiveWallKBT = p.wallKBT > 0.0 ? p.wallKBT : p.wallVpKBT;
        if (effectiveWallKBT < 0.0 && !(p.kBT > 0.0)) {
            throw std::runtime_error("wallKBT/wallVpKBT is negative, so kBT must be positive when solid wall coupling is active");
        }
        if (effectiveWallKBT == 0.0) {
            throw std::runtime_error("wallKBT/wallVpKBT must be positive, or negative to inherit kBT");
        }
    }

    if (p.immersedSolidEnable) {
        std::string solidShape = p.immersedSolidShape;
        std::replace(solidShape.begin(), solidShape.end(), '-', '_');
        if (solidShape != "circle" && solidShape != "disk" && solidShape != "disc" &&
            solidShape != "rectangle" && solidShape != "rect" && solidShape != "box" && solidShape != "step") {
            throw std::runtime_error("immersedSolidShape supports: circle, rectangle");
        }
        if (p.immersedSolidFractionSamples <= 0) {
            throw std::runtime_error("immersedSolidFractionSamples must be positive");
        }

        const double xMax0Solid = p.fluidXMax0 >= 0.0 ? p.fluidXMax0 : p.Lx;
        const double yMax0Solid = p.fluidYMax0 >= 0.0 ? p.fluidYMax0 : p.Ly;
        const double tEndSolid = static_cast<double>(p.nSteps) * p.dt;
        const double xMinEndSolid = p.fluidXMin0 + p.fluidXMinVelocity * tEndSolid;
        const double xMaxEndSolid = xMax0Solid + p.fluidXMaxVelocity * tEndSolid;
        const double yMinEndSolid = p.fluidYMin0 + p.fluidYMinVelocity * tEndSolid;
        const double yMaxEndSolid = yMax0Solid + p.fluidYMaxVelocity * tEndSolid;

        if (solidShape == "circle" || solidShape == "disk" || solidShape == "disc") {
            if (!(p.immersedSolidR > 0.0)) {
                throw std::runtime_error("immersedSolidR/immersedCircleR must be positive when immersedSolidShape=circle");
            }
            const double cxEnd = p.immersedSolidCx + p.immersedSolidVx * tEndSolid;
            const double cyEnd = p.immersedSolidCy + p.immersedSolidVy * tEndSolid;
            const bool circleInsideStart =
                p.immersedSolidCx - p.immersedSolidR >= p.fluidXMin0 &&
                p.immersedSolidCx + p.immersedSolidR <= xMax0Solid &&
                p.immersedSolidCy - p.immersedSolidR >= p.fluidYMin0 &&
                p.immersedSolidCy + p.immersedSolidR <= yMax0Solid;
            const bool circleInsideEnd =
                cxEnd - p.immersedSolidR >= xMinEndSolid &&
                cxEnd + p.immersedSolidR <= xMaxEndSolid &&
                cyEnd - p.immersedSolidR >= yMinEndSolid &&
                cyEnd + p.immersedSolidR <= yMaxEndSolid;
            if (!circleInsideStart || !circleInsideEnd) {
                throw std::runtime_error("The immersed circle must lie inside the active fluid domain at the beginning and end of the run");
            }
        } else {
            if (!(p.immersedSolidXMax > p.immersedSolidXMin) || !(p.immersedSolidYMax > p.immersedSolidYMin)) {
                throw std::runtime_error("immersedSolid rectangle requires XMax>XMin and YMax>YMin");
            }
            if (std::abs(p.immersedSolidOmega) > 0.0) {
                throw std::runtime_error("immersedSolidOmega is currently implemented only for circle; use Omega=0 for rectangle");
            }
            const double xMinEnd = p.immersedSolidXMin + p.immersedSolidVx * tEndSolid;
            const double xMaxEnd = p.immersedSolidXMax + p.immersedSolidVx * tEndSolid;
            const double yMinEnd = p.immersedSolidYMin + p.immersedSolidVy * tEndSolid;
            const double yMaxEnd = p.immersedSolidYMax + p.immersedSolidVy * tEndSolid;
            const bool rectInsideStart =
                p.immersedSolidXMin >= p.fluidXMin0 && p.immersedSolidXMax <= xMax0Solid &&
                p.immersedSolidYMin >= p.fluidYMin0 && p.immersedSolidYMax <= yMax0Solid;
            const bool rectInsideEnd =
                xMinEnd >= xMinEndSolid && xMaxEnd <= xMaxEndSolid &&
                yMinEnd >= yMinEndSolid && yMaxEnd <= yMaxEndSolid;
            if (!rectInsideStart || !rectInsideEnd) {
                throw std::runtime_error("The immersed rectangle must lie inside the active fluid domain at the beginning and end of the run");
            }
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
    // 0259: classic SRC CUDA mode is a durable operator-level short-circuit
    // for the incompressible closure. Keep accepting legacy Q6/virial
    // parameter blocks in validation files, but do not validate those blocks as
    // active physics when the classic mode is selected.
    const bool classicSrcCudaMode = p.srcClassicCudaModeEnable;
    const bool q6OrProjectionRequested = p.projectionEnable && !classicSrcCudaMode;
    if (q6OrProjectionRequested) {
        if (p.projectionOperator != "periodic_fv_cg" &&
            p.projectionOperator != "channel_fv_cg" &&
            p.projectionOperator != "auto_fv_cg" &&
            p.projectionOperator != "elliptic_fv_cg") {
            throw std::runtime_error("projectionOperator supports: periodic_fv_cg, channel_fv_cg, auto_fv_cg, elliptic_fv_cg");
        }
        if (p.projectionBackend != "cpu" &&
            p.projectionBackend != "auto" &&
            p.projectionBackend != "cuda") {
            throw std::runtime_error("projectionBackend supports on SRC_GPU/CUDA-only branch: cpu, auto, cuda");
        }
        if (p.projectionMaxIterations < 0) {
            throw std::runtime_error("projectionMaxIterations must be non-negative");
        }
        if (!(p.projectionTolerance > 0.0)) {
            throw std::runtime_error("projectionTolerance must be positive");
        }
        if (!(p.q6ProjectionStrength >= 0.0 && p.q6ProjectionStrength <= 1.0)) {
            throw std::runtime_error("q6ProjectionStrength must lie in [0,1]");
        }
        if (!(p.projectionImmersedSolidFluidFractionThreshold >= 0.0 &&
              p.projectionImmersedSolidFluidFractionThreshold <= 1.0)) {
            throw std::runtime_error("projectionImmersedSolidFluidFractionThreshold must lie in [0,1]");
        }
    }
    parse_species_q6_mode_0491a(p.speciesQ6Mode, "validate_simulation_params");
    parse_species_q6_fallback_0491a(p.speciesQ6FallbackMode, "validate_simulation_params");
    if (!(p.speciesQ6Sensitivity >= 0.0 && p.speciesQ6Sensitivity <= 1.0) ||
        !std::isfinite(p.speciesQ6Sensitivity)) {
        throw std::runtime_error("speciesQ6Sensitivity must lie in [0,1]");
    }
    if (!(p.speciesQ6AlphaEpsilon > 0.0) || !std::isfinite(p.speciesQ6AlphaEpsilon)) {
        throw std::runtime_error("speciesQ6AlphaEpsilon must be finite and positive");
    }
    if (!(p.speciesQ6ComparisonTolerance > 0.0) ||
        !std::isfinite(p.speciesQ6ComparisonTolerance)) {
        throw std::runtime_error("speciesQ6ComparisonTolerance must be finite and positive");
    }
    if (!(p.speciesQ6MinOccupancyFraction >= 0.0 &&
          p.speciesQ6MinOccupancyFraction <= 1.0) ||
        !std::isfinite(p.speciesQ6MinOccupancyFraction)) {
        throw std::runtime_error("speciesQ6MinOccupancyFraction must lie in [0,1]");
    }
    const bool maskedSpeciesQ60493x5a =
        p.speciesQ6Mode == "independent_masked" ||
        p.speciesQ6Mode == "free_surface_masked";
    if (maskedSpeciesQ60493x5a) {
        for (const SpeciesDefinition& d : p.speciesDefinitions) {
            if (d.q6StrengthDeclared > 1.0) {
                throw std::runtime_error(
                    "masked species Q6 requires q6StrengthDeclared in [0,1]");
            }
            if (!(d.referenceCellMassDeclared > 0.0) ||
                !std::isfinite(d.referenceCellMassDeclared)) {
                throw std::runtime_error(
                    "masked species Q6 requires positive finite referenceCellMassDeclared");
            }
        }
    }
    if (p.speciesQ6Enable) {
        if (!p.speciesRegistryEnable) {
            throw std::runtime_error("speciesQ6Enable=true requires speciesRegistryEnable=true");
        }
        if (!q6OrProjectionRequested) {
            throw std::runtime_error("speciesQ6Enable=true requires active Q6 projection");
        }
    }
    if (p.closedCapacityResponseEnable && !classicSrcCudaMode) {
        if (!(p.closedCapacityReferenceCellMass >= 0.0) || !std::isfinite(p.closedCapacityReferenceCellMass)) {
            throw std::runtime_error("closedCapacityReferenceCellMass must be finite and non-negative; use 0 to infer it");
        }
        if (!(p.closedCapacityReferenceParticleMass > 0.0) || !std::isfinite(p.closedCapacityReferenceParticleMass)) {
            throw std::runtime_error("closedCapacityReferenceParticleMass must be finite and positive");
        }
        if (!(p.closedCapacityQ6Eta > 0.0) || !(p.closedCapacityQ6Power > 0.0) ||
            !std::isfinite(p.closedCapacityQ6Eta) || !std::isfinite(p.closedCapacityQ6Power)) {
            throw std::runtime_error("closedCapacityQ6Eta and closedCapacityQ6Power must be finite and positive");
        }
        if (!(p.closedCapacityMassRemapEta > 0.0) || !(p.closedCapacityMassRemapPower > 0.0) ||
            !std::isfinite(p.closedCapacityMassRemapEta) || !std::isfinite(p.closedCapacityMassRemapPower)) {
            throw std::runtime_error("closedCapacityMassRemapEta and closedCapacityMassRemapPower must be finite and positive");
        }
        if (!(p.closedCapacityInletMassFluxMultiplier >= 0.0) || !std::isfinite(p.closedCapacityInletMassFluxMultiplier)) {
            throw std::runtime_error("closedCapacityInletMassFluxMultiplier must be finite and non-negative");
        }
        if (!(p.closedCapacityVirialBaseK >= 0.0) || !(p.closedCapacityVirialGain >= 0.0) ||
            !(p.closedCapacityVirialEta > 0.0) || !(p.closedCapacityVirialPower > 0.0) ||
            !(p.closedCapacityVirialKickStrength >= 0.0) ||
            !std::isfinite(p.closedCapacityVirialBaseK) || !std::isfinite(p.closedCapacityVirialGain) ||
            !std::isfinite(p.closedCapacityVirialEta) || !std::isfinite(p.closedCapacityVirialPower) ||
            !std::isfinite(p.closedCapacityVirialKickStrength)) {
            throw std::runtime_error("closedCapacityVirial* parameters must be finite; K/gain/kickStrength non-negative, eta/power positive");
        }
        const bool refCanBeInferred = p.closedCapacityReferenceCellMass > 0.0 ||
                                      p.resamplingTargetCellMass > 0.0 ||
                                      p.inletTargetOccupancy > 0;
        if (!refCanBeInferred) {
            throw std::runtime_error("closedCapacityResponseEnable=true requires closedCapacityReferenceCellMass>0, or resamplingTargetCellMass>0, or inletTargetOccupancy>0");
        }
    }
    if (q6OrProjectionRequested &&
        p.immersedSolidEnable && !p.projectionImmersedSolidMaskEnable && !p.projectionAllowUnmaskedImmersedSolid) {
        throw std::runtime_error("Q6 with immersedSolidEnable requires projectionImmersedSolidMaskEnable=true; use projectionAllowUnmaskedImmersedSolid=true only for explicit debug controls");
    }
    if (q6OrProjectionRequested &&
        p.immersedSolidEnable && p.projectionImmersedSolidMaskEnable &&
        (std::abs(p.immersedSolidVx) > 0.0 || std::abs(p.immersedSolidVy) > 0.0 || std::abs(p.immersedSolidOmega) > 0.0)) {
        throw std::runtime_error("Q6 immersed-solid projection mask currently supports fixed immersed solids only");
    }
    if (p.q6ForceProjectionMode != "legacy" &&
        p.q6ForceProjectionMode != "prestream" &&
        p.q6ForceProjectionMode != "prestream_single" &&
        p.q6ForceProjectionMode != "prestream_single_fused") {
        throw std::runtime_error(
            "q6ForceProjectionMode supports: legacy, prestream, prestream_single, prestream_single_fused");
    }
    if (p.q6ForceProjectionMode != "legacy") {
        const bool periodicBox = is_x_periodic(p) && is_y_periodic(p);
        const auto staticWall = [](const std::string& mode) {
            return mode == "solid" || mode == "specular";
        };
        const bool closedStaticBox = !is_x_periodic(p) && !is_y_periodic(p) &&
            staticWall(p.bcLeft) && staticWall(p.bcRight) &&
            staticWall(p.bcBottom) && staticWall(p.bcTop);
        if (!q6OrProjectionRequested || p.projectionBackend != "cuda") {
            throw std::runtime_error(
                "non-legacy q6ForceProjectionMode requires active CUDA Q6 projection");
        }
        if (!periodicBox && !closedStaticBox) {
            throw std::runtime_error(
                "non-legacy q6ForceProjectionMode is restricted to periodic boxes or static closed boxes");
        }
        const bool freeSurfaceMasked0493x5a =
            p.speciesQ6Enable && p.speciesQ6Mode == "free_surface_masked";
        if (p.speciesQ6Enable && p.speciesQ6Mode != "common" &&
            !freeSurfaceMasked0493x5a) {
            throw std::runtime_error(
                "non-legacy q6ForceProjectionMode currently requires speciesQ6Mode=common "
                "or free_surface_masked");
        }
        if (freeSurfaceMasked0493x5a) {
            if (p.q6ForceProjectionMode != "prestream_single_fused") {
                throw std::runtime_error(
                    "free_surface_masked requires q6ForceProjectionMode=prestream_single_fused");
            }
            if (!closedStaticBox) {
                throw std::runtime_error(
                    "free_surface_masked 0493x5a is restricted to a static closed box");
            }
            int projectedSpecies0493x5a = 0;
            for (const SpeciesDefinition& d : p.speciesDefinitions) {
                if (d.q6StrengthDeclared > 0.0) ++projectedSpecies0493x5a;
            }
            if (projectedSpecies0493x5a != 1) {
                throw std::runtime_error(
                    "free_surface_masked 0493x5a requires exactly one species with q6StrengthDeclared>0");
            }
        }
        // 0493x6f-r1: allow resampling only for the already-restricted
        // free_surface_masked + prestream_single_fused static closed-box path.
        // Keep all other historical non-legacy exclusions unchanged.
        const bool allowFreeSurfaceResampling0493x6fr1 =
            freeSurfaceMasked0493x5a &&
            p.q6ForceProjectionMode == "prestream_single_fused";
        if ((p.resamplingEnable && !allowFreeSurfaceResampling0493x6fr1) ||
            p.closedCapacityResponseEnable ||
            p.closedCapacityVirialKickEnable || p.darcyBrinkmanEnable ||
            p.immersedSolidEnable || p.projectionImmersedSolidMaskEnable ||
            p.openBoundarySegmentsEnable) {
            throw std::runtime_error(
                "non-legacy q6ForceProjectionMode test excludes capacity/virial, Darcy, immersed solids, open boundaries, and resampling outside free_surface_masked prestream_single_fused");
        }
        if (std::abs(p.fluidXMinVelocity) > 0.0 || std::abs(p.fluidXMaxVelocity) > 0.0 ||
            std::abs(p.fluidYMinVelocity) > 0.0 || std::abs(p.fluidYMaxVelocity) > 0.0) {
            throw std::runtime_error(
                "non-legacy q6ForceProjectionMode requires a static fluid domain");
        }
    }
    if (p.taylorGreenForcingEnable) {
        if (!(p.Lx > 0.0) || !(p.Ly > 0.0)) {
            throw std::runtime_error("Taylor--Green forcing requires positive Lx and Ly");
        }
        if (!(p.taylorGreenForcingAmplitude >= 0.0)) {
            throw std::runtime_error("taylorGreenForcingAmplitude must be non-negative");
        }
        if (p.taylorGreenForcingModeX <= 0 || p.taylorGreenForcingModeY <= 0) {
            throw std::runtime_error("taylorGreenForcingModeX/Y must be positive integers");
        }
        if (!is_x_periodic(p) || !is_y_periodic(p)) {
            throw std::runtime_error("Taylor--Green forcing is currently restricted to periodic-x/periodic-y runs");
        }
    }
    if (!(p.resamplingTargetCellMass >= 0.0)) {
        throw std::runtime_error("resamplingTargetCellMass must be non-negative; use 0 to infer the current mean real-fluid cell mass");
    }
    if (p.resamplingWetMaskMode != "active_domain" && p.resamplingWetMaskMode != "occupied") {
        throw std::runtime_error("resamplingWetMaskMode supports: active_domain, occupied");
    }
    if (!(p.resamplingWetCellMassThreshold >= 0.0)) {
        throw std::runtime_error("resamplingWetCellMassThreshold must be non-negative");
    }
    if (!(p.resamplingPoorCellMassFraction >= 0.0)) {
        throw std::runtime_error("resamplingPoorCellMassFraction must be non-negative");
    }
    if (!(p.resamplingRichCellMassFraction > p.resamplingPoorCellMassFraction)) {
        throw std::runtime_error("resamplingRichCellMassFraction must be greater than resamplingPoorCellMassFraction");
    }
    if (!(p.resamplingActiveFluidFractionThreshold >= 0.0 && p.resamplingActiveFluidFractionThreshold <= 1.0)) {
        throw std::runtime_error("resamplingActiveFluidFractionThreshold must lie in [0,1]");
    }
    const bool localSupportSplitOnly0493o1 =
        p.resamplingEnable && p.resamplingInsertionEnable &&
        !p.resamplingExtractionEnable && !p.resamplingRemapEnable;
    if (p.resamplingInsertionEnable && !p.resamplingExtractionEnable &&
        !localSupportSplitOnly0493o1) {
        throw std::runtime_error(
            "resamplingInsertionEnable without extraction is reserved for the 0493o1 "
            "local-support split-only mode and requires resamplingEnable=true and resamplingRemapEnable=false");
    }
    if (p.resamplingMassGuardEnable && !p.resamplingRemapEnable) {
        throw std::runtime_error("resamplingMassGuardEnable currently requires resamplingRemapEnable=true");
    }
    if (p.resamplingMassRenormalizationPeriod < 0) {
        throw std::runtime_error("resamplingMassRenormalizationPeriod must be non-negative; use 0 to disable mass remap/guard");
    }
    if (!(p.resamplingParticleMassMin >= 0.0)) {
        throw std::runtime_error("resamplingParticleMassMin must be non-negative");
    }
    if (!(p.resamplingParticleMassMax > p.resamplingParticleMassMin)) {
        throw std::runtime_error("resamplingParticleMassMax must be greater than resamplingParticleMassMin");
    }
    if (p.resamplingLatentActivationEnable && p.resamplingLatentActivationMaxPerCell <= 0) {
        throw std::runtime_error("resamplingLatentActivationMaxPerCell must be positive when latent activation is enabled");
    }
    if (!(p.resamplingLatentActivationParticleMass >= 0.0)) {
        throw std::runtime_error("resamplingLatentActivationParticleMass must be non-negative; use 0 to infer target/maxPerCell");
    }
    if (p.resamplingEnable) {
        if (p.resamplingPopulationNMin < 0 || p.resamplingPopulationNTarget < 0 || p.resamplingPopulationNMax < 0) {
            throw std::runtime_error("resamplingPopulationNMin/NTarget/NMax must be non-negative; use 0 to infer defaults");
        }
        const bool allPopulationBoundsExplicit =
            p.resamplingPopulationNMin > 0 && p.resamplingPopulationNTarget > 0 && p.resamplingPopulationNMax > 0;
        const bool allPopulationBoundsInferred =
            p.resamplingPopulationNMin == 0 && p.resamplingPopulationNTarget == 0 && p.resamplingPopulationNMax == 0;
        if (localSupportSplitOnly0493o1) {
            if (!p.speciesRegistryEnable || p.speciesDefinitions.empty() ||
                !p.speciesRequireRegisteredTypes) {
                throw std::runtime_error(
                    "0493o1 local-support split-only mode requires a non-empty strict species registry");
            }
            if (!allPopulationBoundsExplicit) {
                throw std::runtime_error(
                    "0493o1 local-support split-only mode requires explicit positive "
                    "resamplingPopulationNMin/NTarget/NMax");
            }
            if (p.resamplingPopulationMaxSplitsPerCell <= 0 ||
                p.resamplingPopulationMaxSplitsPerStep <= 0) {
                throw std::runtime_error(
                    "0493o1 local-support split-only mode requires positive split caps");
            }
            if (p.cudaResamplingEmptyRefillEnable) {
                throw std::runtime_error(
                    "0493o1 first patch keeps cudaResamplingEmptyRefillEnable=false");
            }
            if (p.speciesResamplingTransferEnable ||
                p.speciesResamplingTransferCudaEnable ||
                p.speciesResamplingMassClosureEnable ||
                p.speciesResamplingMassClosureCudaEnable) {
                throw std::runtime_error(
                    "0493o1 split-only mode requires species transfer and mass closure disabled");
            }
        }
        if (!allPopulationBoundsExplicit && !allPopulationBoundsInferred) {
            throw std::runtime_error("resamplingEnable=true requires either all population bounds NMin/NTarget/NMax positive, or all three set to 0 for inferred defaults");
        }
        if (allPopulationBoundsExplicit && !(p.resamplingPopulationNMin < p.resamplingPopulationNTarget &&
                                            p.resamplingPopulationNTarget < p.resamplingPopulationNMax)) {
            throw std::runtime_error("resamplingPopulationNMin < resamplingPopulationNTarget < resamplingPopulationNMax is required when bounds are explicit");
        }
        if (!(p.resamplingPopulationNMinFraction > 0.0 && p.resamplingPopulationNMinFraction <= 1.0)) {
            throw std::runtime_error("resamplingPopulationNMinFraction must lie in (0,1]");
        }
        if (!(p.resamplingPopulationNMaxFraction >= 1.0)) {
            throw std::runtime_error("resamplingPopulationNMaxFraction must be >= 1");
        }
        if (p.resamplingPopulationMaxSplitsPerCell < 0 || p.resamplingPopulationMaxSplitsPerStep < 0 ||
            p.resamplingPopulationMaxExtractionsPerCell < 0 || p.resamplingPopulationMaxExtractionsPerStep < 0) {
            throw std::runtime_error("resampling population guard per-cell/per-step limits must be non-negative");
        }
    }
    if (!(p.cudaResamplingEmptyRefillTargetFraction > 0.0 && p.cudaResamplingEmptyRefillTargetFraction <= 1.0)) {
        throw std::runtime_error("cudaResamplingEmptyRefillTargetFraction must lie in (0,1]");
    }
    if (p.cudaResamplingEmptyRefillReference != "ntarget" &&
        p.cudaResamplingEmptyRefillReference != "n_target" &&
        p.cudaResamplingEmptyRefillReference != "gamma") {
        throw std::runtime_error("cudaResamplingEmptyRefillReference supports: nTarget, gamma");
    }
    if (p.cudaResamplingEmptyRefillGamma < 0) {
        throw std::runtime_error("cudaResamplingEmptyRefillGamma must be non-negative; use 0 to infer");
    }
    if (p.cudaResamplingEmptyRefillMemoryMaxAge < 0) {
        throw std::runtime_error("cudaResamplingEmptyRefillMemoryMaxAge must be non-negative; use 0 for unlimited age");
    }
    if (!(p.cudaResamplingChiMin >= 0.0 && p.cudaResamplingChiMin <= 1.0) || !std::isfinite(p.cudaResamplingChiMin)) {
        throw std::runtime_error("cudaResamplingChiMin must lie in [0,1]");
    }
    if (p.darcyBrinkmanEnable) {
        if (p.resamplingEnable && !p.cudaResamplingChiFilterEnable) {
            throw std::runtime_error("darcyBrinkmanEnable=true with resamplingEnable=true requires cudaResamplingChiFilterEnable=true");
        }
        if (!(p.darcyChiMode == "uniform" || p.darcyChiMode == "circle" || p.darcyChiMode == "cylinder" ||
              p.darcyChiMode == "box" || p.darcyChiMode == "rectangle" || p.darcyChiMode == "file")) {
            throw std::runtime_error("darcyChiMode supports: uniform, circle/cylinder, box/rectangle, file");
        }
        if (!(p.darcyUniformChi >= 0.0 && p.darcyUniformChi <= 1.0) || !std::isfinite(p.darcyUniformChi)) {
            throw std::runtime_error("darcyUniformChi must lie in [0,1]");
        }
        if (p.darcyChiMode == "file") {
            if (p.darcyChiFile.empty()) {
                throw std::runtime_error("darcyChiMode=file requires darcyChiFile");
            }
            if (p.darcyChiNx != p.Nx || p.darcyChiNy != p.Ny) {
                throw std::runtime_error("darcyChiMode=file requires darcyChiNx=Nx and darcyChiNy=Ny in patch 0345");
            }
            if (!(p.darcyChiFileFormat == "float32" || p.darcyChiFileFormat == "f32" ||
                  p.darcyChiFileFormat == "float64" || p.darcyChiFileFormat == "f64" ||
                  p.darcyChiFileFormat == "double")) {
                throw std::runtime_error("darcyChiFileFormat supports: float32/f32 or float64/f64/double");
            }
        }
        if (!(p.darcyAlphaMin >= 0.0) || !(p.darcyAlphaMax >= p.darcyAlphaMin) ||
            !std::isfinite(p.darcyAlphaMin) || !std::isfinite(p.darcyAlphaMax)) {
            throw std::runtime_error("darcyAlphaMin/Max must be finite and satisfy 0 <= min <= max");
        }
        if (!(p.darcyQ > 0.0) || !std::isfinite(p.darcyQ)) {
            throw std::runtime_error("darcyQ must be finite and positive");
        }
        if (!(p.darcyCircleR >= 0.0) || !std::isfinite(p.darcyCircleR)) {
            throw std::runtime_error("darcyCircleR must be finite and non-negative");
        }
        if (!(p.darcyInterfaceWidth >= 0.0) || !std::isfinite(p.darcyInterfaceWidth)) {
            throw std::runtime_error("darcyInterfaceWidth must be finite and non-negative");
        }
        if (p.darcyChiMode == "box" || p.darcyChiMode == "rectangle") {
            if (!(p.darcyBoxXMax >= p.darcyBoxXMin && p.darcyBoxYMax >= p.darcyBoxYMin)) {
                throw std::runtime_error("darcy box mode requires darcyBoxXMax>=darcyBoxXMin and darcyBoxYMax>=darcyBoxYMin");
            }
        }
        if (p.darcyCostEvery < 0) {
            throw std::runtime_error("darcyCostEvery must be non-negative");
        }
        if (p.darcyThreadsPerBlock <= 0) {
            throw std::runtime_error("darcyThreadsPerBlock must be positive");
        }
        if (!(p.darcyInitialDeactivateBelowChi < 0.0 ||
              (p.darcyInitialDeactivateBelowChi >= 0.0 && p.darcyInitialDeactivateBelowChi <= 1.0)) ||
            !std::isfinite(p.darcyInitialDeactivateBelowChi)) {
            throw std::runtime_error("darcyInitialDeactivateBelowChi must be negative to disable or lie in [0,1]");
        }
        {
            std::string mode = p.darcyBrinkmanForcingMode;
            std::replace(mode.begin(), mode.end(), '-', '_');
            if (!(mode == "mean" || mode == "classic" || mode == "cell_mean" ||
                  mode == "thermal_bath" || mode == "thermalbath" || mode == "langevin" || mode == "ou" ||
                  mode == "outward_bath" || mode == "oriented_bath" || mode == "oriented_thermal_bath" ||
                  mode == "diffuse_reflection" ||
                  mode == "mean_outward_bath" || mode == "mean_oriented_bath" || mode == "brinkman_outward_bath")) {
                throw std::runtime_error("darcyBrinkmanForcingMode supports: mean/classic/cell_mean, thermal_bath/langevin/ou, outward_bath/oriented_bath, or mean_outward_bath");
            }
            const bool thermalBath = (mode == "thermal_bath" || mode == "thermalbath" || mode == "langevin" || mode == "ou" ||
                                      mode == "outward_bath" || mode == "oriented_bath" || mode == "oriented_thermal_bath" ||
                                      mode == "diffuse_reflection" ||
                                      mode == "mean_outward_bath" || mode == "mean_oriented_bath" || mode == "brinkman_outward_bath");
            if (thermalBath) {
                const double effectiveWallKBT = p.wallKBT > 0.0 ? p.wallKBT : (p.wallVpKBT > 0.0 ? p.wallVpKBT : p.kBT);
                if (!(effectiveWallKBT > 0.0) || !std::isfinite(effectiveWallKBT)) {
                    throw std::runtime_error("darcyBrinkmanForcingMode=thermal_bath requires positive wallKBT/wallVpKBT or positive kBT");
                }
            }
        }
        if (p.darcyChiCollisionVpEnable) {
            if (!p.darcyBrinkmanEnable) {
                throw std::runtime_error("darcyChiCollisionVpEnable=true requires darcyBrinkmanEnable=true so that the chi field is available");
            }
            std::string vpMode = p.darcyChiCollisionVpMode;
            std::replace(vpMode.begin(), vpMode.end(), '-', '_');
            if (!(vpMode == "interface_band" || vpMode == "interface" || vpMode == "band")) {
                throw std::runtime_error("darcyChiCollisionVpMode supports interface_band only in patch 0422");
            }
            if (!std::isfinite(p.darcyChiCollisionVpGamma)) {
                throw std::runtime_error("darcyChiCollisionVpGamma must be finite; use <=0 for wallVpGamma/inferred fallback");
            }
            if (!(p.darcyChiCollisionVpMass > 0.0) || !std::isfinite(p.darcyChiCollisionVpMass)) {
                throw std::runtime_error("darcyChiCollisionVpMass must be positive and finite");
            }
            if (p.darcyChiCollisionVpLayers < 0 || p.darcyChiCollisionVpLayers > 4) {
                throw std::runtime_error("darcyChiCollisionVpLayers must be in [0,4] for the lightweight 0422 kernel");
            }
            if (!(p.darcyChiCollisionVpThreshold >= 0.0 && p.darcyChiCollisionVpThreshold <= 1.0) ||
                !std::isfinite(p.darcyChiCollisionVpThreshold)) {
                throw std::runtime_error("darcyChiCollisionVpThreshold must lie in [0,1]");
            }
            if (!(p.darcyChiCollisionVpStrength >= 0.0) || !std::isfinite(p.darcyChiCollisionVpStrength)) {
                throw std::runtime_error("darcyChiCollisionVpStrength must be non-negative and finite");
            }
        }
        if (p.topoBenchmarkEvery < 0) {
            throw std::runtime_error("topoBenchmarkEvery must be non-negative");
        }
        if (!std::isfinite(p.topoBenchmarkFlowDirX) || !std::isfinite(p.topoBenchmarkFlowDirY) ||
            std::hypot(p.topoBenchmarkFlowDirX, p.topoBenchmarkFlowDirY) <= 0.0) {
            throw std::runtime_error("topoBenchmark flow direction must be finite and non-zero");
        }
        if (!std::isfinite(p.topoBenchmarkLiftDirX) || !std::isfinite(p.topoBenchmarkLiftDirY) ||
            std::hypot(p.topoBenchmarkLiftDirX, p.topoBenchmarkLiftDirY) <= 0.0) {
            throw std::runtime_error("topoBenchmark lift direction must be finite and non-zero");
        }
    }
    if (p.speciesDiagnosticsEnable && p.speciesDiagnosticsFilename.empty()) {
        throw std::runtime_error(
            "speciesDiagnosticsEnable=true requires a non-empty speciesDiagnosticsFilename");
    }
    if (p.speciesCellDiagnosticsEnable && p.speciesCellDiagnosticsFilename.empty()) {
        throw std::runtime_error(
            "speciesCellDiagnosticsEnable=true requires a non-empty speciesCellDiagnosticsFilename");
    }
    if (p.speciesCellDiagnosticsEnable && !p.speciesRegistryEnable) {
        throw std::runtime_error(
            "speciesCellDiagnosticsEnable=true requires speciesRegistryEnable=true");
    }
    if (p.speciesCellCudaDepositEnable) {
        if (!p.speciesRegistryEnable) {
            throw std::runtime_error(
                "speciesCellCudaDepositEnable=true requires speciesRegistryEnable=true");
        }
        if (!p.speciesRequireRegisteredTypes) {
            throw std::runtime_error(
                "speciesCellCudaDepositEnable=true requires speciesRequireRegisteredTypes=true");
        }
        if (p.speciesCellCudaComparisonFilename.empty()) {
            throw std::runtime_error(
                "speciesCellCudaDepositEnable=true requires a non-empty speciesCellCudaComparisonFilename");
        }
        if (!(p.speciesCellCudaComparisonTolerance >= 0.0) ||
            !std::isfinite(p.speciesCellCudaComparisonTolerance)) {
            throw std::runtime_error(
                "speciesCellCudaComparisonTolerance must be finite and non-negative");
        }
        if (p.speciesCellCudaThreadsPerBlock <= 0 ||
            p.speciesCellCudaThreadsPerBlock > 1024) {
            throw std::runtime_error(
                "speciesCellCudaThreadsPerBlock must lie in [1,1024]");
        }
    }
    if (p.cudaResamplingEmptyRefillSpeciesCompositionEnable) {
        if (!p.speciesRegistryEnable) {
            throw std::runtime_error(
                "cudaResamplingEmptyRefillSpeciesCompositionEnable=true requires speciesRegistryEnable=true");
        }
        if (!p.speciesRequireRegisteredTypes) {
            throw std::runtime_error(
                "cudaResamplingEmptyRefillSpeciesCompositionEnable=true requires speciesRequireRegisteredTypes=true");
        }
        if (!p.cudaResamplingEmptyRefillEnable) {
            throw std::runtime_error(
                "cudaResamplingEmptyRefillSpeciesCompositionEnable=true requires cudaResamplingEmptyRefillEnable=true");
        }
    }
    if (p.speciesResamplingPopulationGuardEnable) {
        if (!p.speciesRegistryEnable) {
            throw std::runtime_error(
                "speciesResamplingPopulationGuardEnable=true requires speciesRegistryEnable=true");
        }
        if (!p.speciesRequireRegisteredTypes) {
            throw std::runtime_error(
                "speciesResamplingPopulationGuardEnable=true requires speciesRequireRegisteredTypes=true");
        }
        if (!p.resamplingEnable) {
            throw std::runtime_error(
                "speciesResamplingPopulationGuardEnable=true requires resamplingEnable=true");
        }
    }
    if (p.speciesResamplingPopulationGuardCudaEnable) {
        if (!p.speciesResamplingPopulationGuardEnable) {
            throw std::runtime_error(
                "speciesResamplingPopulationGuardCudaEnable=true requires speciesResamplingPopulationGuardEnable=true");
        }
        if (p.resamplingPopulationNTarget <= 0 || p.resamplingPopulationNMin <= 0 ||
            p.resamplingPopulationNMax <= 0) {
            throw std::runtime_error(
                "speciesResamplingPopulationGuardCudaEnable=true requires explicit positive resamplingPopulationNMin/NTarget/NMax");
        }
    }
    if (p.speciesResamplingTransferEnable) {
        if (!p.speciesRegistryEnable) {
            throw std::runtime_error(
                "speciesResamplingTransferEnable=true requires speciesRegistryEnable=true");
        }
        if (!p.speciesRequireRegisteredTypes) {
            throw std::runtime_error(
                "speciesResamplingTransferEnable=true requires speciesRequireRegisteredTypes=true");
        }
        if (!p.resamplingEnable || !p.resamplingExtractionEnable || !p.resamplingInsertionEnable) {
            throw std::runtime_error(
                "speciesResamplingTransferEnable=true requires resampling, extraction and insertion");
        }
    }
    if (p.speciesResamplingTransferCudaEnable) {
        if (!p.speciesResamplingTransferEnable) {
            throw std::runtime_error(
                "speciesResamplingTransferCudaEnable=true requires speciesResamplingTransferEnable=true");
        }
        if (!(p.speciesTransferCudaComparisonTolerance > 0.0) ||
            !std::isfinite(p.speciesTransferCudaComparisonTolerance)) {
            throw std::runtime_error(
                "speciesTransferCudaComparisonTolerance must be finite and positive");
        }
        if (p.speciesTransferCudaDiagnosticsFilename.empty()) {
            throw std::runtime_error(
                "speciesTransferCudaDiagnosticsFilename must not be empty");
        }
    }
    if (p.speciesResamplingCudaResidentValidationEnable ||
        p.speciesResamplingCudaResidentFastPathEnable) {
        const char* mode = p.speciesResamplingCudaResidentFastPathEnable
            ? "speciesResamplingCudaResidentFastPathEnable"
            : "speciesResamplingCudaResidentValidationEnable";
        if (!p.speciesResamplingTransferCudaEnable) {
            throw std::runtime_error(
                std::string(mode) + "=true requires speciesResamplingTransferCudaEnable=true");
        }
        if (!p.speciesRegistryEnable || !p.speciesRequireRegisteredTypes) {
            throw std::runtime_error(
                std::string(mode) + "=true requires a strict registered species registry");
        }
        if (!p.resamplingEnable || !p.resamplingExtractionEnable || !p.resamplingInsertionEnable) {
            throw std::runtime_error(
                std::string(mode) + "=true requires resampling extraction/insertion");
        }
    }
    if (p.speciesResamplingCudaResidentFastPathEnable) {
        if (p.speciesResamplingCudaResidentValidationEnable) {
            throw std::runtime_error(
                "speciesResamplingCudaResidentFastPathEnable and speciesResamplingCudaResidentValidationEnable are mutually exclusive");
        }
        // 0493a: topology-only qualification guard removed.
        // The 0490m/n/p resident chain now consumes the current shared
        // CUDA state for every already-supported boundary family.

        if (p.speciesCudaResidentFastPathDiagnosticsFilename.empty()) {
            throw std::runtime_error(
                "speciesCudaResidentFastPathDiagnosticsFilename must not be empty");
        }
        if (p.resamplingLatentActivationEnable) {
            throw std::runtime_error(
                "0490m resident fast path currently requires resamplingLatentActivationEnable=false");
        }
        if (p.speciesResamplingPopulationGuardEnable &&
            !p.speciesResamplingPopulationGuardCudaEnable) {
            throw std::runtime_error(
                "0490m resident fast path requires the CUDA species population guard when the guard is enabled");
        }
        if (p.speciesResamplingMassClosureEnable &&
            !p.speciesResamplingMassClosureCudaEnable) {
            throw std::runtime_error(
                "0490m resident fast path requires the CUDA species mass closure when mass closure is enabled");
        }
        if (p.resamplingThermalRenormalizationEnable) {
            throw std::runtime_error(
                "0490m resident fast path currently requires resamplingThermalRenormalizationEnable=false");
        }
    }
    if (p.speciesResamplingCudaResidentDepositsEnable ||
        p.speciesResamplingCudaResidentPoolEnable ||
        p.speciesResamplingCudaResidentMaintenanceStrict) {
        if (!p.speciesResamplingCudaResidentFastPathEnable) {
            throw std::runtime_error(
                "0490n resident maintenance requires speciesResamplingCudaResidentFastPathEnable=true");
        }
        if (p.speciesCudaResidentMaintenanceDiagnosticsFilename.empty()) {
            throw std::runtime_error(
                "speciesCudaResidentMaintenanceDiagnosticsFilename must not be empty");
        }
        if (p.speciesResamplingCudaResidentMaintenanceStrict &&
            (!p.speciesResamplingCudaResidentDepositsEnable ||
             !p.speciesResamplingCudaResidentPoolEnable)) {
            throw std::runtime_error(
                "0490n strict maintenance requires both resident deposits and resident pool");
        }
        const bool fullStaticDomain0490n =
            p.fluidXMin0 == 0.0 && p.fluidYMin0 == 0.0 &&
            (p.fluidXMax0 < 0.0 || p.fluidXMax0 == p.Lx) &&
            (p.fluidYMax0 < 0.0 || p.fluidYMax0 == p.Ly) &&
            p.fluidXMinVelocity == 0.0 && p.fluidXMaxVelocity == 0.0 &&
            p.fluidYMinVelocity == 0.0 && p.fluidYMaxVelocity == 0.0;
        if (!fullStaticDomain0490n) {
            throw std::runtime_error(
                "0490p resident device cell policy currently requires the full static fluid domain");
        }
        if (p.resamplingLatentActivationEnable) {
            throw std::runtime_error(
                "0490n resident pool currently requires resamplingLatentActivationEnable=false");
        }
        if (p.resamplingThermalRenormalizationEnable) {
            throw std::runtime_error(
                "0490p resident device cell policy currently requires resamplingThermalRenormalizationEnable=false");
        }
    }
    if (p.speciesResamplingMassClosureEnable) {
        if (!p.speciesRegistryEnable) {
            throw std::runtime_error(
                "speciesResamplingMassClosureEnable=true requires speciesRegistryEnable=true");
        }
        if (!p.speciesRequireRegisteredTypes) {
            throw std::runtime_error(
                "speciesResamplingMassClosureEnable=true requires speciesRequireRegisteredTypes=true");
        }
        if (!p.resamplingEnable || !p.resamplingRemapEnable) {
            throw std::runtime_error(
                "speciesResamplingMassClosureEnable=true requires resamplingEnable=true and resamplingRemapEnable=true");
        }
        if (p.resamplingMassGuardEnable) {
            throw std::runtime_error(
                "0490d species-aware mass closure does not yet support resamplingMassGuardEnable=true");
        }
        if (p.closedCapacityResponseEnable) {
            throw std::runtime_error(
                "0490d species-aware mass closure does not yet support closedCapacityResponseEnable=true");
        }
    }
    if (p.speciesResamplingMassClosureCudaEnable) {
        if (!p.speciesResamplingMassClosureEnable) {
            throw std::runtime_error(
                "speciesResamplingMassClosureCudaEnable=true requires speciesResamplingMassClosureEnable=true");
        }
        if (p.resamplingThermalRenormalizationEnable) {
            throw std::runtime_error(
                "0490i resident CUDA species mass closure does not yet support resamplingThermalRenormalizationEnable=true");
        }
        if (p.speciesMassClosureCudaDiagnosticsFilename.empty()) {
            throw std::runtime_error(
                "speciesResamplingMassClosureCudaEnable=true requires a non-empty speciesMassClosureCudaDiagnosticsFilename");
        }
        if (!(p.speciesMassClosureCudaComparisonTolerance >= 0.0) ||
            !std::isfinite(p.speciesMassClosureCudaComparisonTolerance)) {
            throw std::runtime_error(
                "speciesMassClosureCudaComparisonTolerance must be finite and non-negative");
        }
    }
    if (p.speciesRegistryEnable) {
        validate_species_definitions(p.speciesDefinitions, "validate_simulation_params species registry");
        for (const OpenBoundarySegment& seg : p.openBoundarySegments) {
            if (is_inlet_boundary_mode(seg.mode) &&
                find_species_definition(p.speciesDefinitions, seg.type) == nullptr) {
                throw std::runtime_error(
                    "Inlet segment uses unregistered species type " + std::to_string(seg.type));
            }
        }
    }
    if (p.summaryEvery <= 0) {
        throw std::runtime_error("summaryEvery must be positive");
    }
    if (p.dumpStateEvery < 0) {
        throw std::runtime_error("dumpStateEvery must be non-negative");
    }
    if (!(p.dumpRoleFilter == "all" || p.dumpRoleFilter == "fluid")) {
        throw std::runtime_error("dumpRoleFilter must be 'all' or 'fluid'");
    }
    if (!(p.summaryRoleFilter == "all" || p.summaryRoleFilter == "fluid")) {
        throw std::runtime_error("summaryRoleFilter must be 'all' or 'fluid'");
    }
    if (p.numThreads < 0) {
        throw std::runtime_error("numThreads must be non-negative");
    }
}

} // namespace mpcd
