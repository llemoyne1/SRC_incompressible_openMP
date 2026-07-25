#include "species_registry.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <iomanip>
#include <limits>
#include <map>
#include <set>
#include <sstream>
#include <stdexcept>

namespace mpcd {
namespace {

std::string lower_copy(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return value;
}

struct SpeciesAccumulator0490a {
    SpeciesDefinition definition{};
    bool registered = false;
    std::uint64_t nFluid = 0u;
    std::uint64_t nLatent = 0u;
    double totalMass = 0.0;
    double px = 0.0;
    double py = 0.0;
    double kineticEnergy = 0.0;
    double minParticleMass = std::numeric_limits<double>::infinity();
    double maxParticleMass = 0.0;
};

std::string csv_safe_name0490a(std::string value) {
    for (char& c : value) {
        if (c == ',' || c == '\n' || c == '\r') c = '_';
    }
    return value;
}

} // namespace

const char* species_phase_family_name(SpeciesPhaseFamily family) {
    switch (family) {
        case SpeciesPhaseFamily::Gas: return "gas";
        case SpeciesPhaseFamily::Liquid: return "liquid";
        case SpeciesPhaseFamily::Dispersed: return "dispersed";
        default: return "unspecified";
    }
}

SpeciesPhaseFamily parse_species_phase_family(const std::string& value,
                                              const std::string& context) {
    const std::string v = lower_copy(value);
    if (v == "gas") return SpeciesPhaseFamily::Gas;
    if (v == "liquid") return SpeciesPhaseFamily::Liquid;
    if (v == "dispersed" || v == "colloid" || v == "colloidal") {
        return SpeciesPhaseFamily::Dispersed;
    }
    if (v == "unspecified" || v == "unknown" || v == "legacy") {
        return SpeciesPhaseFamily::Unspecified;
    }
    throw std::runtime_error(context + ": phase family must be gas, liquid, dispersed or unspecified");
}

void validate_species_definitions(const std::vector<SpeciesDefinition>& definitions,
                                  const std::string& context) {
    std::set<std::uint32_t> types;
    std::set<std::string> names;
    for (const SpeciesDefinition& d : definitions) {
        if (d.name.empty()) {
            throw std::runtime_error(context + ": species name must not be empty");
        }
        if (!types.insert(d.type).second) {
            throw std::runtime_error(context + ": duplicate species type " + std::to_string(d.type));
        }
        const std::string normalizedName = lower_copy(d.name);
        if (!names.insert(normalizedName).second) {
            throw std::runtime_error(context + ": duplicate species name '" + d.name + "'");
        }
        if (!std::isfinite(d.q6StrengthDeclared) || d.q6StrengthDeclared < 0.0) {
            throw std::runtime_error(context + ": q6StrengthDeclared must be finite and non-negative for type " +
                                     std::to_string(d.type));
        }
        if (!std::isfinite(d.resamplingMassClosureStrengthDeclared) ||
            d.resamplingMassClosureStrengthDeclared < 0.0 ||
            d.resamplingMassClosureStrengthDeclared > 1.0) {
            throw std::runtime_error(context +
                                     ": resamplingMassClosureStrengthDeclared must lie in [0,1] for type " +
                                     std::to_string(d.type));
        }
        if (!std::isfinite(d.referenceCellMassDeclared) ||
            !(d.referenceCellMassDeclared > 0.0)) {
            throw std::runtime_error(context +
                                     ": referenceCellMassDeclared must be finite and positive for type " +
                                     std::to_string(d.type));
        }
    }
}

const SpeciesDefinition* find_species_definition(
    const std::vector<SpeciesDefinition>& definitions,
    std::uint32_t type) {
    const auto it = std::find_if(definitions.begin(), definitions.end(),
                                 [type](const SpeciesDefinition& d) { return d.type == type; });
    return it == definitions.end() ? nullptr : &(*it);
}

void validate_state_species_registry(const ParticleState& state,
                                     const std::vector<SpeciesDefinition>& definitions,
                                     bool requireRegisteredTypes,
                                     const std::string& context) {
    validate_particle_state(state, context);
    if (!requireRegisteredTypes) return;

    for (std::size_t i = 0; i < static_cast<std::size_t>(state.Np); ++i) {
        const std::uint8_t role = particle_role_value(state, i);
        if (is_inactive_role(role)) continue;
        if (find_species_definition(definitions, state.type[i]) == nullptr) {
            std::ostringstream oss;
            oss << context << ": unregistered transported species type=" << state.type[i]
                << " at particle=" << i
                << " role=" << particle_role_name(role);
            throw std::runtime_error(oss.str());
        }
    }
}

SpeciesDiagnosticsWriter0490a::SpeciesDiagnosticsWriter0490a(const std::string& filepath)
    : out_(filepath) {
    if (!out_) {
        throw std::runtime_error("Cannot open species diagnostics file for writing: " + filepath);
    }
    out_ << "step,time,type,name,phaseFamily,registered,q6StrengthDeclared,"
            "resamplingMassClosureStrengthDeclared,referenceCellMassDeclared,resamplingEnable,nFluid,nLatent,totalMass,Px,Py,"
            "kineticEnergy,meanVx,meanVy,meanParticleMass,minParticleMass,maxParticleMass\n";
}

void SpeciesDiagnosticsWriter0490a::append(
    const ParticleState& state,
    const std::vector<SpeciesDefinition>& definitions,
    bool requireRegisteredTypes,
    std::uint64_t step,
    double time) {
    validate_state_species_registry(state, definitions, requireRegisteredTypes,
                                    "SpeciesDiagnosticsWriter0490a::append");

    std::map<std::uint32_t, SpeciesAccumulator0490a> rows;
    for (const SpeciesDefinition& d : definitions) {
        SpeciesAccumulator0490a acc{};
        acc.definition = d;
        acc.registered = true;
        rows.emplace(d.type, std::move(acc));
    }

    for (std::size_t i = 0; i < static_cast<std::size_t>(state.Np); ++i) {
        const std::uint8_t role = particle_role_value(state, i);
        if (is_inactive_role(role)) continue;

        const std::uint32_t type = state.type[i];
        auto [it, inserted] = rows.try_emplace(type);
        SpeciesAccumulator0490a& acc = it->second;
        if (inserted) {
            acc.definition.type = type;
            acc.definition.name = "unregistered_" + std::to_string(type);
            acc.definition.phaseFamily = SpeciesPhaseFamily::Unspecified;
            acc.definition.q6StrengthDeclared = 0.0;
            acc.definition.resamplingMassClosureStrengthDeclared = 0.0;
            acc.definition.referenceCellMassDeclared = 1.0;
            acc.registered = false;
        }

        if (is_latent_role(role)) {
            ++acc.nLatent;
            continue;
        }
        if (!is_fluid_role(role)) continue;

        const double m = state.mass[i];
        const double vx = state.vx[i];
        const double vy = state.vy[i];
        ++acc.nFluid;
        acc.totalMass += m;
        acc.px += m * vx;
        acc.py += m * vy;
        acc.kineticEnergy += 0.5 * m * (vx * vx + vy * vy);
        acc.minParticleMass = std::min(acc.minParticleMass, m);
        acc.maxParticleMass = std::max(acc.maxParticleMass, m);
    }

    for (const auto& entry : rows) {
        const SpeciesAccumulator0490a& acc = entry.second;
        const double invMass = acc.totalMass > 0.0 ? 1.0 / acc.totalMass : 0.0;
        const double invCount = acc.nFluid > 0u ? 1.0 / static_cast<double>(acc.nFluid) : 0.0;
        const double minMass = acc.nFluid > 0u ? acc.minParticleMass : 0.0;
        out_ << step << ','
             << std::setprecision(17) << time << ','
             << acc.definition.type << ','
             << csv_safe_name0490a(acc.definition.name) << ','
             << species_phase_family_name(acc.definition.phaseFamily) << ','
             << (acc.registered ? 1 : 0) << ','
             << acc.definition.q6StrengthDeclared << ','
             << acc.definition.resamplingMassClosureStrengthDeclared << ','
             << acc.definition.referenceCellMassDeclared << ','
             << (acc.definition.resamplingEnable ? 1 : 0) << ','
             << acc.nFluid << ','
             << acc.nLatent << ','
             << acc.totalMass << ','
             << acc.px << ','
             << acc.py << ','
             << acc.kineticEnergy << ','
             << acc.px * invMass << ','
             << acc.py * invMass << ','
             << acc.totalMass * invCount << ','
             << minMass << ','
             << acc.maxParticleMass << '\n';
    }
    out_.flush();
}

} // namespace mpcd
