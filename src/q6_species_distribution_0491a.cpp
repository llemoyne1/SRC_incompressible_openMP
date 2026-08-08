#include "q6_species_distribution_0491a.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <limits>
#include <stdexcept>

namespace mpcd {
namespace {

std::string lower_copy_0491a(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return value;
}

double max_abs_0491a(double current, double value) {
    return std::max(current, std::abs(value));
}

} // namespace

std::size_t q6_species_flat_index_0491a(std::size_t speciesIndex,
                                        int cell,
                                        int numCells) {
    if (numCells <= 0 || cell < 0 || cell >= numCells) {
        throw std::runtime_error("q6_species_flat_index_0491a: invalid cell index");
    }
    return speciesIndex * static_cast<std::size_t>(numCells) +
           static_cast<std::size_t>(cell);
}

SpeciesQ6Mode0491a parse_species_q6_mode_0491a(const std::string& value,
                                                const std::string& context) {
    const std::string v = lower_copy_0491a(value);
    if (v == "common") return SpeciesQ6Mode0491a::Common;
    if (v == "weighted") return SpeciesQ6Mode0491a::Weighted;
    if (v == "independent_masked") return SpeciesQ6Mode0491a::IndependentMasked;
    if (v == "free_surface_masked") return SpeciesQ6Mode0491a::FreeSurfaceMasked;
    throw std::runtime_error(
        context + ": speciesQ6Mode must be common, weighted, independent_masked "
                  "or free_surface_masked");
}

SpeciesQ6Fallback0491a parse_species_q6_fallback_0491a(const std::string& value,
                                                        const std::string& context) {
    const std::string v = lower_copy_0491a(value);
    if (v == "common") return SpeciesQ6Fallback0491a::Common;
    if (v == "fatal") return SpeciesQ6Fallback0491a::Fatal;
    throw std::runtime_error(context + ": speciesQ6FallbackMode must be common or fatal");
}

SpeciesQ6DistributionResult0491a compute_q6_species_distribution_0491a(
    const SpeciesQ6DistributionInput0491a& input) {
    if (input.numCells <= 0) {
        throw std::runtime_error("0491a species-Q6 distribution requires numCells>0");
    }
    if (input.speciesCount <= 0) {
        throw std::runtime_error("0491a species-Q6 distribution requires speciesCount>0");
    }
    if (input.sensitivity < 0.0 || input.sensitivity > 1.0 ||
        !std::isfinite(input.sensitivity)) {
        throw std::runtime_error("0491a speciesQ6Sensitivity must lie in [0,1]");
    }
    if (!(input.alphaEpsilon > 0.0) || !std::isfinite(input.alphaEpsilon)) {
        throw std::runtime_error("0491a speciesQ6AlphaEpsilon must be finite and positive");
    }
    if (!(input.minOccupancyFraction >= 0.0 && input.minOccupancyFraction <= 1.0) ||
        !std::isfinite(input.minOccupancyFraction)) {
        throw std::runtime_error(
            "0493w5 speciesQ6MinOccupancyFraction must lie in [0,1]");
    }

    const std::size_t nc = static_cast<std::size_t>(input.numCells);
    const std::size_t ns = static_cast<std::size_t>(input.speciesCount);
    const std::size_t dense = nc * ns;
    if (input.speciesMass.size() != dense ||
        input.q6Alpha.size() != ns ||
        input.cellDUx.size() != nc ||
        input.cellDUy.size() != nc) {
        throw std::runtime_error("0491a species-Q6 distribution input has inconsistent dimensions");
    }
    const bool maskedMode0493x5a =
        input.mode == SpeciesQ6Mode0491a::IndependentMasked ||
        input.mode == SpeciesQ6Mode0491a::FreeSurfaceMasked;
    if (maskedMode0493x5a && input.referenceCellMass.size() != ns) {
        throw std::runtime_error(
            "masked species Q6 requires one referenceCellMass per species");
    }

    for (std::size_t s = 0; s < ns; ++s) {
        const double a = input.q6Alpha[s];
        if (!std::isfinite(a) || a < 0.0) {
            throw std::runtime_error("0491a q6 alpha must be finite and non-negative");
        }
        if (maskedMode0493x5a) {
            const double ref = input.referenceCellMass[s];
            if (!(ref > 0.0) || !std::isfinite(ref)) {
                throw std::runtime_error(
                    "masked species Q6 referenceCellMass must be finite and positive");
            }
            if (a > 1.0) {
                throw std::runtime_error(
                    "masked species Q6 q6 alpha must lie in [0,1]");
            }
        }
    }

    SpeciesQ6DistributionResult0491a result{};
    SpeciesQ6Distribution0491a& out = result.fields;
    out.numCells = input.numCells;
    out.speciesCount = input.speciesCount;
    out.totalCellMass.assign(nc, 0.0);
    out.massFraction.assign(dense, 0.0);
    out.totalOccupancyWeight.assign(nc, 0.0);
    out.occupancyFraction.assign(dense, 0.0);
    out.activeMask.assign(dense, 0u);
    out.alphaBar.assign(nc, 0.0);
    out.weight.assign(dense, 1.0);
    out.speciesDUx.assign(dense, 0.0);
    out.speciesDUy.assign(dense, 0.0);

    SpeciesQ6DistributionSummary0491a& summary = result.summary;
    double weightMassSum = 0.0;
    double weightMassSquareSum = 0.0;
    double relativeVelocityDeltaSquareSum = 0.0;
    double massWeightedCells = 0.0;
    bool sawWeight = false;

    for (int c = 0; c < input.numCells; ++c) {
        const std::size_t cc = static_cast<std::size_t>(c);
        double totalMass = 0.0;
        std::uint32_t presentSpecies = 0u;
        for (std::size_t s = 0; s < ns; ++s) {
            const std::size_t k = q6_species_flat_index_0491a(s, c, input.numCells);
            const double m = input.speciesMass[k];
            if (!std::isfinite(m) || m < 0.0) {
                throw std::runtime_error("0491a species mass must be finite and non-negative");
            }
            totalMass += m;
            if (m > 0.0) ++presentSpecies;
        }
        out.totalCellMass[cc] = totalMass;
        if (totalMass <= 0.0) {
            ++summary.emptyCells;
            continue;
        }
        ++summary.wetCells;
        if (presentSpecies <= 1u) {
            ++summary.pureCells;
        } else {
            ++summary.mixedCells;
        }

        double alphaBar = 0.0;
        double totalOccupancyWeight = 0.0;
        for (std::size_t s = 0; s < ns; ++s) {
            const std::size_t k = q6_species_flat_index_0491a(s, c, input.numCells);
            const double y = input.speciesMass[k] / totalMass;
            out.massFraction[k] = y;
            alphaBar += y * input.q6Alpha[s];
            if (maskedMode0493x5a) {
                totalOccupancyWeight += input.speciesMass[k] / input.referenceCellMass[s];
            }
        }
        out.alphaBar[cc] = alphaBar;
        out.totalOccupancyWeight[cc] = totalOccupancyWeight;
        if (maskedMode0493x5a && totalOccupancyWeight > 0.0) {
            for (std::size_t s = 0; s < ns; ++s) {
                const std::size_t k = q6_species_flat_index_0491a(s, c, input.numCells);
                const double fill = input.speciesMass[k] / input.referenceCellMass[s];
                out.occupancyFraction[k] =
                    input.mode == SpeciesQ6Mode0491a::FreeSurfaceMasked
                        ? fill
                        : fill / totalOccupancyWeight;
            }
        }

        if (maskedMode0493x5a) {
            bool cellProjected = false;
            for (std::size_t s = 0; s < ns; ++s) {
                const std::size_t k = q6_species_flat_index_0491a(s, c, input.numCells);
                const bool active = input.speciesMass[k] > 0.0 &&
                    input.q6Alpha[s] > 0.0 &&
                    out.occupancyFraction[k] >= input.minOccupancyFraction;
                const double w = active ? input.q6Alpha[s] : 0.0;
                out.activeMask[k] = active ? 1u : 0u;
                out.weight[k] = w;
                out.speciesDUx[k] = w * input.cellDUx[cc];
                out.speciesDUy[k] = w * input.cellDUy[cc];
                if (active) {
                    ++summary.projectedSpeciesCellPairs;
                    cellProjected = true;
                } else if (input.speciesMass[k] > 0.0) {
                    ++summary.suppressedSpeciesCellPairs;
                }
                if (input.q6Alpha[s] == 0.0) {
                    summary.maxAbsDisabledSpeciesCorrection = std::max(
                        summary.maxAbsDisabledSpeciesCorrection,
                        std::hypot(out.speciesDUx[k], out.speciesDUy[k]));
                }
                if (input.speciesMass[k] > 0.0) {
                    summary.weightMin = sawWeight ? std::min(summary.weightMin, w) : w;
                    summary.weightMax = sawWeight ? std::max(summary.weightMax, w) : w;
                    sawWeight = true;
                    const double y = out.massFraction[k];
                    weightMassSum += y * w;
                    weightMassSquareSum += y * w * w;
                    const double dw = w - 1.0;
                    relativeVelocityDeltaSquareSum +=
                        y * dw * dw *
                        (input.cellDUx[cc] * input.cellDUx[cc] +
                         input.cellDUy[cc] * input.cellDUy[cc]);
                }
            }
            if (cellProjected) ++summary.projectedCells;
            massWeightedCells += 1.0;
            // A barycentric residual is intentionally not an invariant of the
            // independent path: q6Strength=0 means zero direct correction.
            continue;
        }

        const bool commonMode =
            input.mode == SpeciesQ6Mode0491a::Common || input.sensitivity == 0.0;
        bool useCommon = commonMode;
        if (!useCommon && alphaBar < input.alphaEpsilon) {
            ++summary.alphaFallbackCells;
            if (input.fallback == SpeciesQ6Fallback0491a::Fatal) {
                throw std::runtime_error("0491a species-Q6 alphaBar below epsilon in fatal mode");
            }
            useCommon = true;
        }

        double residualX = -totalMass * input.cellDUx[cc];
        double residualY = -totalMass * input.cellDUy[cc];
        for (std::size_t s = 0; s < ns; ++s) {
            const std::size_t k = q6_species_flat_index_0491a(s, c, input.numCells);
            const double y = out.massFraction[k];
            const double w = useCommon
                ? 1.0
                : (1.0 - input.sensitivity) + input.sensitivity * input.q6Alpha[s] / alphaBar;
            if (!std::isfinite(w)) {
                throw std::runtime_error("0491a species-Q6 produced a non-finite weight");
            }
            out.weight[k] = w;
            out.speciesDUx[k] = w * input.cellDUx[cc];
            out.speciesDUy[k] = w * input.cellDUy[cc];
            residualX += input.speciesMass[k] * out.speciesDUx[k];
            residualY += input.speciesMass[k] * out.speciesDUy[k];

            if (input.speciesMass[k] > 0.0) {
                summary.weightMin = sawWeight ? std::min(summary.weightMin, w) : w;
                summary.weightMax = sawWeight ? std::max(summary.weightMax, w) : w;
                sawWeight = true;
                weightMassSum += y * w;
                weightMassSquareSum += y * w * w;
                const double dw = w - 1.0;
                relativeVelocityDeltaSquareSum +=
                    y * dw * dw *
                    (input.cellDUx[cc] * input.cellDUx[cc] +
                     input.cellDUy[cc] * input.cellDUy[cc]);
            }
        }
        massWeightedCells += 1.0;
        summary.maxAbsBarycentricResidualX =
            max_abs_0491a(summary.maxAbsBarycentricResidualX, residualX);
        summary.maxAbsBarycentricResidualY =
            max_abs_0491a(summary.maxAbsBarycentricResidualY, residualY);
    }

    if (massWeightedCells > 0.0) {
        summary.weightMassMean = weightMassSum / massWeightedCells;
        summary.weightMassRms = std::sqrt(weightMassSquareSum / massWeightedCells);
        summary.relativeVelocityDeltaRms =
            std::sqrt(relativeVelocityDeltaSquareSum / massWeightedCells);
    }
    return result;
}

} // namespace mpcd
