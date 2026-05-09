#include "params_io.h"

#include <algorithm>
#include <cctype>
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <unordered_map>

namespace mpcd {
namespace {

std::string trim(const std::string& s) {
    std::size_t b = 0;
    while (b < s.size() && std::isspace(static_cast<unsigned char>(s[b]))) { ++b; }
    std::size_t e = s.size();
    while (e > b && std::isspace(static_cast<unsigned char>(s[e - 1]))) { --e; }
    return s.substr(b, e - b);
}

std::unordered_map<std::string, std::string> read_kv_map(const std::string& filepath) {
    std::ifstream fin(filepath);
    if (!fin) {
        throw std::runtime_error("Cannot open params file: " + filepath);
    }
    std::unordered_map<std::string, std::string> kv;
    std::string line;
    while (std::getline(fin, line)) {
        line = trim(line);
        if (line.empty() || line[0] == '#') {
            continue;
        }
        const auto pos = line.find('=');
        if (pos == std::string::npos) {
            throw std::runtime_error("Invalid key=value line in params file: " + line);
        }
        const std::string key = trim(line.substr(0, pos));
        const std::string value = trim(line.substr(pos + 1));
        kv[key] = value;
    }
    return kv;
}

template <typename T>
T parse_number(const std::string& s);

template <>
int parse_number<int>(const std::string& s) {
    return std::stoi(s);
}

template <>
double parse_number<double>(const std::string& s) {
    return std::stod(s);
}

bool parse_bool(const std::string& s) {
    if (s == "true" || s == "1") return true;
    if (s == "false" || s == "0") return false;
    throw std::runtime_error("Invalid boolean value: " + s);
}

const std::string& require_key(const std::unordered_map<std::string, std::string>& kv,
                               const std::string& key) {
    auto it = kv.find(key);
    if (it == kv.end()) {
        throw std::runtime_error("Missing required params key: " + key);
    }
    return it->second;
}
std::string get_string_or(
    const std::unordered_map<std::string, std::string>& kv,
    const std::string& key,
    const std::string& defaultValue
) {
    auto it = kv.find(key);
    return (it == kv.end()) ? defaultValue : it->second;
}

int get_int_or(
    const std::unordered_map<std::string, std::string>& kv,
    const std::string& key,
    int defaultValue
) {
    auto it = kv.find(key);
    return (it == kv.end()) ? defaultValue : parse_number<int>(it->second);
}

double get_double_or(
    const std::unordered_map<std::string, std::string>& kv,
    const std::string& key,
    double defaultValue
) {
    auto it = kv.find(key);
    return (it == kv.end()) ? defaultValue : parse_number<double>(it->second);
}

bool get_bool_or(
    const std::unordered_map<std::string, std::string>& kv,
    const std::string& key,
    bool defaultValue
) {
    auto it = kv.find(key);
    return (it == kv.end()) ? defaultValue : parse_bool(it->second);
}
} // namespace

Params read_params_kv(const std::string& filepath) {
    const auto kv = read_kv_map(filepath);
    Params p{};

    p.Nx = parse_number<int>(require_key(kv, "Nx"));
    p.Ny = parse_number<int>(require_key(kv, "Ny"));
    p.Nc = parse_number<int>(require_key(kv, "Nc"));
    p.n = parse_number<int>(require_key(kv, "n"));
    p.Lx = parse_number<double>(require_key(kv, "Lx"));
    p.Ly = parse_number<double>(require_key(kv, "Ly"));
    p.dt = parse_number<double>(require_key(kv, "dt"));
    p.a0 = parse_number<double>(require_key(kv, "a0"));

    p.alpha = parse_number<double>(require_key(kv, "alpha"));
    p.kBT = parse_number<double>(require_key(kv, "kBT"));
    p.g = parse_number<double>(require_key(kv, "g"));
    p.bodyForceX = parse_number<double>(require_key(kv, "bodyForceX"));
    p.useThermostat = parse_bool(require_key(kv, "useThermostat"));
    p.keepMeanFlow = parse_bool(require_key(kv, "keepMeanFlow"));

    p.boundary_left = require_key(kv, "boundary_left");
    p.boundary_right = require_key(kv, "boundary_right");
    p.boundary_bottom = require_key(kv, "boundary_bottom");
    p.boundary_top = require_key(kv, "boundary_top");
    p.Utop = parse_number<double>(require_key(kv, "Utop"));
    p.Ubottom = parse_number<double>(require_key(kv, "Ubottom"));
    p.wallSigma = parse_number<double>(require_key(kv, "wallSigma"));

    p.noSurfaceCase = parse_bool(require_key(kv, "noSurfaceCase"));
    p.redistributionEnableSurfaceTopology = parse_bool(require_key(kv, "redistributionEnableSurfaceTopology"));
    p.redistributionWallWettingEnabled = parse_bool(require_key(kv, "redistributionWallWettingEnabled"));
    p.useInterfaceVelocityReorientation = parse_bool(require_key(kv, "useInterfaceVelocityReorientation"));
    p.useIncompressibleRedistribution = parse_bool(require_key(kv, "useIncompressibleRedistribution"));
    p.redistribAfterCollision = parse_bool(require_key(kv, "redistribAfterCollision"));
    p.useZoneRedistribution = parse_bool(require_key(kv, "useZoneRedistribution"));
    p.zoneTileNx = parse_number<int>(require_key(kv, "zoneTileNx"));
    p.zoneTileNy = parse_number<int>(require_key(kv, "zoneTileNy"));
    p.zoneUseShiftedSecondPass = parse_bool(require_key(kv, "zoneUseShiftedSecondPass"));
    p.zonePassthroughMode = parse_bool(require_key(kv, "zonePassthroughMode"));
    p.zoneSingleFullDomainMode = parse_bool(require_key(kv, "zoneSingleFullDomainMode"));
    p.enableMomentumCorrectionPostRedistribution = parse_bool(require_key(kv, "enableMomentumCorrectionPostRedistribution"));
    p.gamma = parse_number<double>(require_key(kv, "gamma"));
    p.coef = parse_number<double>(require_key(kv, "coef"));
    p.highMode = require_key(kv, "highMode");
    p.lowMode = require_key(kv, "lowMode");
    p.maxRedistribPasses = parse_number<int>(require_key(kv, "maxRedistribPasses"));
    p.useLocalFluidFractionThresholds = parse_bool(require_key(kv, "useLocalFluidFractionThresholds"));
    p.fluidFracGain = parse_number<double>(require_key(kv, "fluidFracGain"));
    p.lowThrFloor = parse_number<double>(require_key(kv, "lowThrFloor"));
    p.highThrFloor = parse_number<double>(require_key(kv, "highThrFloor"));
    p.lowThrBulkOverride = parse_number<double>(require_key(kv, "lowThrBulkOverride"));

    p.useLiquidClosure = parse_bool(require_key(kv, "useLiquidClosure"));
    p.useOptimalBetaRepair = parse_bool(require_key(kv, "useOptimalBetaRepair"));
    p.betaRepair = parse_number<double>(require_key(kv, "betaRepair"));
    p.betaEOS = parse_number<double>(require_key(kv, "betaEOS"));
    p.Kvirial = parse_number<double>(require_key(kv, "Kvirial"));
    p.smoothPdriveAtInterzone = parse_bool(require_key(kv, "smoothPdriveAtInterzone"));
    p.smoothPdriveInterzoneWidthCells = parse_number<int>(require_key(kv, "smoothPdriveInterzoneWidthCells"));
    p.smoothPdriveInterzoneBlend = parse_number<double>(require_key(kv, "smoothPdriveInterzoneBlend"));
    p.smoothPdriveIncludeShiftedLayouts = parse_bool(require_key(kv, "smoothPdriveIncludeShiftedLayouts"));

  p.visualEnable = get_bool_or(kv, "visualEnable", false);
  p.visualEvery = get_int_or(kv, "visualEvery", 20);
  p.visualMode = get_string_or(kv, "visualMode", "field_particles");
  p.visualField = get_string_or(kv, "visualField", "speed");
  p.visualFieldAutoScale = get_bool_or(kv, "visualFieldAutoScale", true);
  p.visualFieldMin = get_double_or(kv, "visualFieldMin", 0.0);
  p.visualFieldMax = get_double_or(kv, "visualFieldMax", 1.0);
    p.visualFieldSmoothingEnable = get_bool_or(kv, "visualFieldSmoothingEnable", false);
    p.visualFieldSmoothingPasses = get_int_or(kv, "visualFieldSmoothingPasses", 1);
    p.visualFieldMinOccupancy = get_int_or(kv, "visualFieldMinOccupancy", 1);
    p.visualFieldTemporalAverageEnable = get_bool_or(kv, "visualFieldTemporalAverageEnable", false);
    p.visualFieldTemporalAlpha = get_double_or(kv, "visualFieldTemporalAlpha", 0.90);
    p.visualFieldRobustScaleEnable = get_bool_or(kv, "visualFieldRobustScaleEnable", false);
    p.visualFieldRobustScaleLowPercentile = get_double_or(kv, "visualFieldRobustScaleLowPercentile", 2.0);
    p.visualFieldRobustScaleHighPercentile = get_double_or(kv, "visualFieldRobustScaleHighPercentile", 98.0);
  p.visualShowParticles = get_bool_or(kv, "visualShowParticles", true);
  p.visualMaxParticles = get_int_or(kv, "visualMaxParticles", 10000);
  p.visualPointSize = get_double_or(kv, "visualPointSize", 2.0);
  p.visualParticleColorMode = get_string_or(kv, "visualParticleColorMode", "speed");
  p.visualWindowWidth = get_int_or(kv, "visualWindowWidth", 1100);
  p.visualWindowHeight = get_int_or(kv, "visualWindowHeight", 850);

  p.obstacleEnable = get_bool_or(kv, "obstacleEnable", false);
  p.obstacleType = get_string_or(kv, "obstacleType", "none");
  p.obstacleCx = get_double_or(kv, "obstacleCx", 0.5 * p.Lx);
  p.obstacleCy = get_double_or(kv, "obstacleCy", 0.5 * p.Ly);
  p.obstacleRadius = get_double_or(kv, "obstacleRadius", 0.0);


  p.wakeDiagnosticsEnable = get_bool_or(kv, "wakeDiagnosticsEnable", false);
  p.wakeDiagnosticsEvery = get_int_or(kv, "wakeDiagnosticsEvery", 0);
  p.wakeProbe1XOverD = get_double_or(kv, "wakeProbe1XOverD", 1.0);
  p.wakeProbe2XOverD = get_double_or(kv, "wakeProbe2XOverD", 2.0);
  p.wakeProbe3XOverD = get_double_or(kv, "wakeProbe3XOverD", 4.0);
  p.wakeProbe4XOverD = get_double_or(kv, "wakeProbe4XOverD", 6.0);
  p.wakeProbeHalfWidthOverD = get_double_or(kv, "wakeProbeHalfWidthOverD", 0.25);
  p.wakeProbeHalfHeightOverD = get_double_or(kv, "wakeProbeHalfHeightOverD", 0.50);
  p.wakeReferenceXMinOverD = get_double_or(kv, "wakeReferenceXMinOverD", -4.0);
  p.wakeReferenceXMaxOverD = get_double_or(kv, "wakeReferenceXMaxOverD", -2.0);
  p.wakeReferenceHalfHeightOverD = get_double_or(kv, "wakeReferenceHalfHeightOverD", 1.0);
    return p;
}

void write_runout_kv(const std::string& filepath, const RunOutStep& runout) {
    std::ofstream fout(filepath);
    if (!fout) {
        throw std::runtime_error("Cannot open runout file for writing: " + filepath);
    }
    fout << "inputTag=" << runout.inputTag << '\n';
    fout << "outputTag=" << runout.outputTag << '\n';
    fout << "pBotInst=" << runout.pBotInst << '\n';
    fout << "pTopInst=" << runout.pTopInst << '\n';
    fout << "pMeanInst=" << runout.pMeanInst << '\n';
    fout << "layoutMode=" << runout.layoutMode << '\n';
    fout << "nZonesExecuted=" << runout.nZonesExecuted << '\n';
}

} // namespace mpcd
