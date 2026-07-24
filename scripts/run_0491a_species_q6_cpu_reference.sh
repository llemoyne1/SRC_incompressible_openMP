#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CXX=${CXX:-g++}
CXXFLAGS=${CXXFLAGS:--std=c++17 -O2 -Wall -Wextra}
TMP_DIR="${TMP_DIR:-/tmp/src_mpcd_0491a}"
BIN="$TMP_DIR/q6_species_distribution_0491a_smoke"
SRC="$TMP_DIR/q6_species_distribution_0491a_smoke.cpp"
mkdir -p "$TMP_DIR"

cat > "$SRC" <<'CPP'
#include "q6_species_distribution_0491a.h"

#include <cmath>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

using namespace mpcd;

void require_close(double got, double expected, double tol, const std::string& label) {
    if (std::abs(got - expected) > tol) {
        throw std::runtime_error(label + " got=" + std::to_string(got) +
                                 " expected=" + std::to_string(expected));
    }
}

void require_true(bool ok, const std::string& label) {
    if (!ok) throw std::runtime_error(label);
}

SpeciesQ6DistributionInput0491a base_input(int cells, int species) {
    SpeciesQ6DistributionInput0491a in{};
    in.numCells = cells;
    in.speciesCount = species;
    in.speciesMass.assign(static_cast<std::size_t>(cells) * static_cast<std::size_t>(species), 0.0);
    in.q6Alpha.assign(static_cast<std::size_t>(species), 1.0);
    in.cellDUx.assign(static_cast<std::size_t>(cells), 0.25);
    in.cellDUy.assign(static_cast<std::size_t>(cells), -0.125);
    in.mode = SpeciesQ6Mode0491a::Weighted;
    in.fallback = SpeciesQ6Fallback0491a::Common;
    in.sensitivity = 1.0;
    return in;
}

int main() {
    const double tol = 1.0e-13;
    require_true(parse_species_q6_mode_0491a("common", "smoke") == SpeciesQ6Mode0491a::Common,
                 "parse common mode");
    require_true(parse_species_q6_mode_0491a("weighted", "smoke") == SpeciesQ6Mode0491a::Weighted,
                 "parse weighted mode");
    require_true(parse_species_q6_fallback_0491a("common", "smoke") == SpeciesQ6Fallback0491a::Common,
                 "parse common fallback");
    require_true(parse_species_q6_fallback_0491a("fatal", "smoke") == SpeciesQ6Fallback0491a::Fatal,
                 "parse fatal fallback");
    {
        auto in = base_input(1, 1);
        in.speciesMass[0] = 4.0;
        in.q6Alpha[0] = 0.2;
        auto r = compute_q6_species_distribution_0491a(in);
        require_close(r.fields.weight[0], 1.0, tol, "S1 mono weight");
        require_close(r.summary.maxAbsBarycentricResidualX, 0.0, tol, "S1 residual x");
        require_true(r.summary.pureCells == 1u, "S1 pure cell count");
    }
    {
        auto in = base_input(1, 2);
        in.speciesMass[0] = 3.0;
        in.speciesMass[1] = 3.0;
        in.q6Alpha[0] = 1.0;
        in.q6Alpha[1] = 1.0;
        auto r = compute_q6_species_distribution_0491a(in);
        require_close(r.fields.weight[0], 1.0, tol, "S2 weight 0");
        require_close(r.fields.weight[1], 1.0, tol, "S2 weight 1");
        require_close(r.summary.maxAbsBarycentricResidualY, 0.0, tol, "S2 residual y");
    }
    {
        auto in = base_input(1, 2);
        in.speciesMass[0] = 1.0;
        in.speciesMass[1] = 1.0;
        in.q6Alpha[0] = 0.0;
        in.q6Alpha[1] = 1.0;
        auto r = compute_q6_species_distribution_0491a(in);
        require_close(r.fields.weight[0], 0.0, tol, "S3 weight 0");
        require_close(r.fields.weight[1], 2.0, tol, "S3 weight 1");
        require_close(r.summary.weightMassMean, 1.0, tol, "S3 mass-weighted mean");
        require_close(r.summary.maxAbsBarycentricResidualX, 0.0, tol, "S3 residual x");
    }
    {
        auto in = base_input(1, 2);
        in.speciesMass[0] = 1.0;
        in.speciesMass[1] = 3.0;
        in.q6Alpha[0] = 0.5;
        in.q6Alpha[1] = 1.0;
        auto r = compute_q6_species_distribution_0491a(in);
        require_close(r.fields.alphaBar[0], 0.875, tol, "S4 alphaBar");
        require_close(r.fields.weight[0], 0.5 / 0.875, tol, "S4 weight 0");
        require_close(r.fields.weight[1], 1.0 / 0.875, tol, "S4 weight 1");
        require_close(r.summary.maxAbsBarycentricResidualX, 0.0, tol, "S4 residual x");
    }
    {
        auto in = base_input(2, 2);
        in.speciesMass[q6_species_flat_index_0491a(0, 0, 2)] = 4.0;
        in.speciesMass[q6_species_flat_index_0491a(1, 1, 2)] = 5.0;
        in.q6Alpha[0] = 0.1;
        in.q6Alpha[1] = 1.0;
        auto r = compute_q6_species_distribution_0491a(in);
        require_close(r.fields.weight[q6_species_flat_index_0491a(0, 0, 2)], 1.0, tol, "S5 pure 0");
        require_close(r.fields.weight[q6_species_flat_index_0491a(1, 1, 2)], 1.0, tol, "S5 pure 1");
        require_true(r.summary.pureCells == 2u, "S5 pure count");
    }
    {
        auto in = base_input(1, 2);
        in.speciesMass[0] = 1.0;
        in.speciesMass[1] = 1.0;
        in.q6Alpha[0] = 0.0;
        in.q6Alpha[1] = 0.0;
        auto r = compute_q6_species_distribution_0491a(in);
        require_true(r.summary.alphaFallbackCells == 1u, "S6 fallback count");
        require_close(r.fields.weight[0], 1.0, tol, "S6 fallback weight 0");
        in.fallback = SpeciesQ6Fallback0491a::Fatal;
        bool threw = false;
        try {
            (void)compute_q6_species_distribution_0491a(in);
        } catch (const std::runtime_error&) {
            threw = true;
        }
        require_true(threw, "S6 fatal fallback");
    }
    std::cout << "[0491a] PASS species-Q6 CPU reference analytic smokes\n";
    return 0;
}
CPP

"$CXX" $CXXFLAGS -Iinclude "$SRC" src/q6_species_distribution_0491a.cpp -o "$BIN"
"$BIN"
