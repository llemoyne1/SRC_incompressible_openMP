#pragma once

#include "particle_state.h"

#include <cstdint>
#include <fstream>
#include <string>
#include <vector>

namespace mpcd {

enum class SpeciesPhaseFamily : std::uint8_t {
    Unspecified = 0u,
    Gas = 1u,
    Liquid = 2u
};

struct SpeciesDefinition {
    std::uint32_t type = 0u;
    std::string name;
    SpeciesPhaseFamily phaseFamily = SpeciesPhaseFamily::Unspecified;

    // 0490a scaffold only: these values are parsed, validated and reported,
    // but are deliberately not consumed by Q6 or resampling yet.
    double q6StrengthDeclared = 1.0;
    double resamplingMassClosureStrengthDeclared = 1.0;

    // Reference mass of a fully occupied cell for this species. 0490b uses
    // it only to construct an occupancy/volume-fraction proxy in diagnostics.
    // It is not yet consumed by Q6 or resampling.
    double referenceCellMassDeclared = 1.0;
};

const char* species_phase_family_name(SpeciesPhaseFamily family);
SpeciesPhaseFamily parse_species_phase_family(const std::string& value,
                                              const std::string& context);

void validate_species_definitions(const std::vector<SpeciesDefinition>& definitions,
                                  const std::string& context);

const SpeciesDefinition* find_species_definition(
    const std::vector<SpeciesDefinition>& definitions,
    std::uint32_t type);

// Strict validation deliberately ignores Inactive pool slots: their type is
// storage metadata and is not yet a physical transported species. Fluid and
// Latent particles must be registered when strict mode is enabled.
void validate_state_species_registry(const ParticleState& state,
                                     const std::vector<SpeciesDefinition>& definitions,
                                     bool requireRegisteredTypes,
                                     const std::string& context);

class SpeciesDiagnosticsWriter0490a {
public:
    explicit SpeciesDiagnosticsWriter0490a(const std::string& filepath);

    void append(const ParticleState& state,
                const std::vector<SpeciesDefinition>& definitions,
                bool requireRegisteredTypes,
                std::uint64_t step,
                double time);

private:
    std::ofstream out_;
};

} // namespace mpcd
