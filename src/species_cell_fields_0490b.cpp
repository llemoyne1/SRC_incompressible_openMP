#include "species_cell_fields_0490b.h"

#include <iomanip>
#include <stdexcept>
#include <unordered_map>

namespace mpcd {
namespace {

std::string csv_safe_0490b(std::string value) {
    for (char& c : value) {
        if (c == ',' || c == '\n' || c == '\r') c = '_';
    }
    return value;
}

} // namespace

std::size_t species_cell_flat_index_0490b(std::size_t speciesIndex,
                                          int cell,
                                          int numCells) {
    if (cell < 0 || cell >= numCells || numCells <= 0) {
        throw std::runtime_error("species_cell_flat_index_0490b: invalid cell index");
    }
    return speciesIndex * static_cast<std::size_t>(numCells) +
           static_cast<std::size_t>(cell);
}

SpeciesCellFields0490b deposit_species_cell_fields_0490b(
    const ParticleState& state,
    const std::vector<SpeciesDefinition>& definitions,
    const CellGrid& grid,
    const SimulationParams& params,
    bool requireRegisteredTypes) {
    validate_state_species_registry(state, definitions, requireRegisteredTypes,
                                    "deposit_species_cell_fields_0490b");
    validate_species_definitions(definitions,
                                 "deposit_species_cell_fields_0490b registry");
    if (definitions.empty()) {
        throw std::runtime_error(
            "deposit_species_cell_fields_0490b requires registered species");
    }
    if (grid.numCells <= 0 || grid.Nx <= 0 || grid.Ny <= 0) {
        throw std::runtime_error("deposit_species_cell_fields_0490b: invalid grid");
    }

    SpeciesCellFields0490b fields{};
    fields.numCells = grid.numCells;
    for (const SpeciesDefinition& d : definitions) fields.speciesTypes.push_back(d.type);

    const std::size_t denseSize =
        definitions.size() * static_cast<std::size_t>(grid.numCells);
    fields.count.assign(denseSize, 0u);
    fields.mass.assign(denseSize, 0.0);
    fields.px.assign(denseSize, 0.0);
    fields.py.assign(denseSize, 0.0);
    fields.kinetic.assign(denseSize, 0.0);
    fields.totalCellMass.assign(static_cast<std::size_t>(grid.numCells), 0.0);
    fields.totalOccupancyWeight.assign(static_cast<std::size_t>(grid.numCells), 0.0);
    fields.activeSpeciesCount.assign(static_cast<std::size_t>(grid.numCells), 0u);
    fields.dominantType.assign(static_cast<std::size_t>(grid.numCells), 0u);
    fields.dominantFractionProxy.assign(static_cast<std::size_t>(grid.numCells), 0.0);
    fields.liquidFractionProxy.assign(static_cast<std::size_t>(grid.numCells), 0.0);
    fields.gasFractionProxy.assign(static_cast<std::size_t>(grid.numCells), 0.0);

    std::unordered_map<std::uint32_t, std::size_t> speciesIndex;
    for (std::size_t s = 0; s < definitions.size(); ++s) {
        speciesIndex.emplace(definitions[s].type, s);
    }

    // Deterministic CPU reference. Patch 0490h compares the resident CUDA
    // species-cell deposit against this path at strict tolerance.
    const std::size_t n = active_fluid_count_size(state);
    for (std::size_t i = 0; i < n; ++i) {
        if (!is_fluid_particle(state, i)) continue;
        const auto it = speciesIndex.find(state.type[i]);
        if (it == speciesIndex.end()) {
            if (requireRegisteredTypes) {
                throw std::runtime_error(
                    "deposit_species_cell_fields_0490b: unregistered transported type " +
                    std::to_string(state.type[i]));
            }
            continue;
        }
        const int c = cell_index_from_position(
            state.x[i], state.y[i], grid, GridShift{}, params);
        const std::size_t k = species_cell_flat_index_0490b(
            it->second, c, grid.numCells);
        const double m = state.mass[i];
        ++fields.count[k];
        fields.mass[k] += m;
        fields.px[k] += m * state.vx[i];
        fields.py[k] += m * state.vy[i];
        fields.kinetic[k] += 0.5 * m *
            (state.vx[i] * state.vx[i] + state.vy[i] * state.vy[i]);
    }

    for (int c = 0; c < grid.numCells; ++c) {
        const std::size_t cc = static_cast<std::size_t>(c);
        double dominantWeight = -1.0;
        std::size_t dominantIndex = 0u;
        for (std::size_t s = 0; s < definitions.size(); ++s) {
            const std::size_t k = species_cell_flat_index_0490b(s, c, grid.numCells);
            const double m = fields.mass[k];
            fields.totalCellMass[cc] += m;
            if (m > 0.0) ++fields.activeSpeciesCount[cc];
            const double weight = m / definitions[s].referenceCellMassDeclared;
            fields.totalOccupancyWeight[cc] += weight;
            if (weight > dominantWeight) {
                dominantWeight = weight;
                dominantIndex = s;
            }
        }

        const double totalWeight = fields.totalOccupancyWeight[cc];
        if (totalWeight <= 0.0) continue;
        fields.dominantType[cc] = definitions[dominantIndex].type;
        fields.dominantFractionProxy[cc] = dominantWeight / totalWeight;
        for (std::size_t s = 0; s < definitions.size(); ++s) {
            const std::size_t k = species_cell_flat_index_0490b(s, c, grid.numCells);
            const double fraction =
                (fields.mass[k] / definitions[s].referenceCellMassDeclared) / totalWeight;
            if (definitions[s].phaseFamily == SpeciesPhaseFamily::Liquid) {
                fields.liquidFractionProxy[cc] += fraction;
            } else if (definitions[s].phaseFamily == SpeciesPhaseFamily::Gas) {
                fields.gasFractionProxy[cc] += fraction;
            }
        }
    }

    return fields;
}

SpeciesCellDiagnosticsWriter0490b::SpeciesCellDiagnosticsWriter0490b(
    const std::string& filepath,
    const CellGrid& grid)
    : out_(filepath), grid_(grid) {
    if (!out_) {
        throw std::runtime_error(
            "Cannot open species-cell diagnostics file: " + filepath);
    }
    if (grid_.numCells <= 0) {
        throw std::runtime_error(
            "SpeciesCellDiagnosticsWriter0490b: invalid grid");
    }
    out_ << "step,time,cell,ix,iy,xCenter,yCenter,type,name,phaseFamily,"
            "count,mass,Px,Py,kinetic,relativeKinetic,ux,uy,occupancyWeight,fractionProxy,totalCellMass,"
            "totalOccupancyWeight,activeSpeciesCount,dominantType,dominantFractionProxy,"
            "liquidFractionProxy,gasFractionProxy\n";
}

void SpeciesCellDiagnosticsWriter0490b::append(
    const ParticleState& state,
    const std::vector<SpeciesDefinition>& definitions,
    const CellGrid& grid,
    const SimulationParams& params,
    bool requireRegisteredTypes,
    std::uint64_t step,
    double time) {
    if (grid.numCells != grid_.numCells || grid.Nx != grid_.Nx || grid.Ny != grid_.Ny) {
        throw std::runtime_error(
            "SpeciesCellDiagnosticsWriter0490b::append: grid changed");
    }
    const SpeciesCellFields0490b fields = deposit_species_cell_fields_0490b(
        state, definitions, grid, params, requireRegisteredTypes);

    out_ << std::setprecision(17);
    for (int c = 0; c < grid.numCells; ++c) {
        const int ix = c % grid.Nx;
        const int iy = c / grid.Nx;
        const double xCenter = (static_cast<double>(ix) + 0.5) * grid.dx;
        const double yCenter = (static_cast<double>(iy) + 0.5) * grid.dy;
        const std::size_t cc = static_cast<std::size_t>(c);
        const double totalWeight = fields.totalOccupancyWeight[cc];
        for (std::size_t s = 0; s < definitions.size(); ++s) {
            const std::size_t k = species_cell_flat_index_0490b(s, c, grid.numCells);
            const double m = fields.mass[k];
            const double occupancyWeight = m / definitions[s].referenceCellMassDeclared;
            const double fraction = totalWeight > 0.0 ? occupancyWeight / totalWeight : 0.0;
            const double invMass = m > 0.0 ? 1.0 / m : 0.0;
            const double relativeKinetic = m > 0.0
                ? fields.kinetic[k] - 0.5 *
                    (fields.px[k] * fields.px[k] + fields.py[k] * fields.py[k]) * invMass
                : 0.0;
            out_ << step << ',' << time << ',' << c << ',' << ix << ',' << iy << ','
                 << xCenter << ',' << yCenter << ',' << definitions[s].type << ','
                 << csv_safe_0490b(definitions[s].name) << ','
                 << species_phase_family_name(definitions[s].phaseFamily) << ','
                 << fields.count[k] << ',' << m << ',' << fields.px[k] << ','
                 << fields.py[k] << ',' << fields.kinetic[k] << ','
                 << relativeKinetic << ',' << fields.px[k] * invMass << ','
                 << fields.py[k] * invMass << ',' << occupancyWeight << ','
                 << fraction << ',' << fields.totalCellMass[cc] << ','
                 << totalWeight << ',' << fields.activeSpeciesCount[cc] << ','
                 << fields.dominantType[cc] << ','
                 << fields.dominantFractionProxy[cc] << ','
                 << fields.liquidFractionProxy[cc] << ','
                 << fields.gasFractionProxy[cc] << '\n';
        }
    }
    out_.flush();
}

} // namespace mpcd
