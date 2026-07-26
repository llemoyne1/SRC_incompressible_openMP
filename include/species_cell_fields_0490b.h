#pragma once

#include "cell_grid.h"
#include "particle_state.h"
#include "species_registry.h"

#include <cstddef>
#include <cstdint>
#include <fstream>
#include <string>
#include <vector>

namespace mpcd {

// Dense CPU reference fields. Layout is species-major:
// flat index = speciesIndex * numCells + cell.
struct SpeciesCellFields0490b {
    int numCells = 0;
    std::vector<std::uint32_t> speciesTypes;
    std::vector<std::uint32_t> count;
    std::vector<double> mass;
    std::vector<double> px;
    std::vector<double> py;
    std::vector<double> kinetic;
    std::vector<double> totalCellMass;
    std::vector<double> totalOccupancyWeight;
    std::vector<std::uint32_t> activeSpeciesCount;
    std::vector<std::uint32_t> dominantType;
    std::vector<double> dominantFractionProxy;
    std::vector<double> liquidFractionProxy;
    std::vector<double> gasFractionProxy;
};

std::size_t species_cell_flat_index_0490b(std::size_t speciesIndex,
                                          int cell,
                                          int numCells);

SpeciesCellFields0490b deposit_species_cell_fields_0490b(
    const ParticleState& state,
    const std::vector<SpeciesDefinition>& definitions,
    const CellGrid& grid,
    const SimulationParams& params,
    bool requireRegisteredTypes);

class SpeciesCellDiagnosticsWriter0490b {
public:
    SpeciesCellDiagnosticsWriter0490b(const std::string& filepath,
                                      const CellGrid& grid);

    void append(const ParticleState& state,
                const std::vector<SpeciesDefinition>& definitions,
                const CellGrid& grid,
                const SimulationParams& params,
                bool requireRegisteredTypes,
                std::uint64_t step,
                double time);

private:
    std::ofstream out_;
    CellGrid grid_{};
};

} // namespace mpcd
