#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace mpcd {

enum class SpeciesQ6Mode0491a : std::uint8_t {
    Common = 0u,
    Weighted = 1u
};

enum class SpeciesQ6Fallback0491a : std::uint8_t {
    Common = 0u,
    Fatal = 1u
};

struct SpeciesQ6DistributionInput0491a {
    int numCells = 0;
    int speciesCount = 0;
    std::vector<double> speciesMass; // species-major: s * numCells + cell
    std::vector<double> q6Alpha;
    std::vector<double> cellDUx;
    std::vector<double> cellDUy;
    SpeciesQ6Mode0491a mode = SpeciesQ6Mode0491a::Common;
    SpeciesQ6Fallback0491a fallback = SpeciesQ6Fallback0491a::Common;
    double sensitivity = 0.0;
    double alphaEpsilon = 1.0e-14;
};

struct SpeciesQ6Distribution0491a {
    int numCells = 0;
    int speciesCount = 0;
    std::vector<double> totalCellMass;
    std::vector<double> massFraction; // species-major
    std::vector<double> alphaBar;
    std::vector<double> weight; // species-major
    std::vector<double> speciesDUx; // species-major
    std::vector<double> speciesDUy; // species-major
};

struct SpeciesQ6DistributionSummary0491a {
    std::uint64_t emptyCells = 0u;
    std::uint64_t wetCells = 0u;
    std::uint64_t pureCells = 0u;
    std::uint64_t mixedCells = 0u;
    std::uint64_t alphaFallbackCells = 0u;
    double weightMin = 0.0;
    double weightMax = 0.0;
    double weightMassMean = 0.0;
    double weightMassRms = 0.0;
    double maxAbsBarycentricResidualX = 0.0;
    double maxAbsBarycentricResidualY = 0.0;
    double relativeVelocityDeltaRms = 0.0;
};

struct SpeciesQ6DistributionResult0491a {
    SpeciesQ6Distribution0491a fields{};
    SpeciesQ6DistributionSummary0491a summary{};
};

std::size_t q6_species_flat_index_0491a(std::size_t speciesIndex,
                                        int cell,
                                        int numCells);

SpeciesQ6Mode0491a parse_species_q6_mode_0491a(const std::string& value,
                                                const std::string& context);

SpeciesQ6Fallback0491a parse_species_q6_fallback_0491a(const std::string& value,
                                                        const std::string& context);

SpeciesQ6DistributionResult0491a compute_q6_species_distribution_0491a(
    const SpeciesQ6DistributionInput0491a& input);

} // namespace mpcd
