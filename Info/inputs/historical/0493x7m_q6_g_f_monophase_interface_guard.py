#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src" / "cuda_q6_resident_0400.cu"
README = ROOT / "README_0493X7M_Q6_G_F_MONOPHASE_INTERFACE_GUARD.md"

def replace_once(text: str, old: str, new: str, label: str) -> str:
    n = text.count(old)
    if n != 1:
        raise SystemExit(f"[0493x7m] ERROR {label}: expected exactly 1 match, got {n}")
    return text.replace(old, new, 1)

text = SRC.read_text()

text = replace_once(
    text,
    '''    double* facePhiGammaY0493x6g,
    int useGasPressure0493x6g,
    int nx,
''',
    '''    double* facePhiGammaY0493x6g,
    int useGasPressure0493x6g,
    int usePhaseInterface0493x7m,
    int nx,
''',
    "kernel signature",
)

text = replace_once(
    text,
    '''        const double alphaC = alpha[c];
        const bool pressureC = carrierMask[c] != 0u && alphaC >= 0.5;
        pressureMask[c] = pressureC ? 1u : 0u;
''',
    '''        const double alphaC = alpha[c];
        // 0493x7m: alpha=0.5 is a phase boundary only when the registry
        // actually contains a gas phase. In an explicitly monophase liquid
        // registry, density fluctuations must not create pressure-release holes.
        const bool pressureC =
            carrierMask[c] != 0u && (!usePhaseInterface0493x7m || alphaC >= 0.5);
        pressureMask[c] = pressureC ? 1u : 0u;
''',
    "center pressure mask",
)

text = replace_once(
    text,
    '''            const double alphaE = alpha[east];
            const bool pressureE = carrierMask[east] != 0u && alphaE >= 0.5;
            const bool cHigh = alphaC >= 0.5 && alphaE < 0.5;
            const bool eHigh = alphaE >= 0.5 && alphaC < 0.5;
            const bool crossing = cHigh || eHigh;
''',
    '''            const double alphaE = alpha[east];
            const bool pressureE =
                carrierMask[east] != 0u &&
                (!usePhaseInterface0493x7m || alphaE >= 0.5);
            const bool cHigh = alphaC >= 0.5 && alphaE < 0.5;
            const bool eHigh = alphaE >= 0.5 && alphaC < 0.5;
            const bool crossing =
                usePhaseInterface0493x7m && (cHigh || eHigh);
''',
    "east face phase gate",
)

text = replace_once(
    text,
    '''            const double alphaN = alpha[north];
            const bool pressureN = carrierMask[north] != 0u && alphaN >= 0.5;
            const bool cHigh = alphaC >= 0.5 && alphaN < 0.5;
            const bool nHigh = alphaN >= 0.5 && alphaC < 0.5;
            const bool crossing = cHigh || nHigh;
''',
    '''            const double alphaN = alpha[north];
            const bool pressureN =
                carrierMask[north] != 0u &&
                (!usePhaseInterface0493x7m || alphaN >= 0.5);
            const bool cHigh = alphaC >= 0.5 && alphaN < 0.5;
            const bool nHigh = alphaN >= 0.5 && alphaC < 0.5;
            const bool crossing =
                usePhaseInterface0493x7m && (cHigh || nHigh);
''',
    "north face phase gate",
)

text = replace_once(
    text,
    '''    const int speciesCount = static_cast<int>(params.speciesDefinitions.size());
    const std::size_t dense = static_cast<std::size_t>(grid.numCells) *
''',
    '''    const int speciesCount = static_cast<int>(params.speciesDefinitions.size());
    // 0493x7m: the registered phase families are authoritative for topology.
    // x5a deliberately registers an absent gas species, so its liquid/vacuum
    // free surface remains alpha-defined.
    const bool registeredGasPhase0493x7m = std::any_of(
        params.speciesDefinitions.begin(), params.speciesDefinitions.end(),
        [](const SpeciesDefinition& d) {
            return d.phaseFamily == SpeciesPhaseFamily::Gas;
        });
    const std::size_t dense = static_cast<std::size_t>(grid.numCells) *
''',
    "registered gas phase detection",
)

text = replace_once(
    text,
    '''                    phaseGasPressureApplySpecies0493x6g
                        ? ws.phaseFacePhiGammaY0493x6g.data() : nullptr,
                    phaseGasPressureApplySpecies0493x6g ? 1 : 0,
                    grid.Nx, grid.Ny, periodicX, periodicY,
''',
    '''                    phaseGasPressureApplySpecies0493x6g
                        ? ws.phaseFacePhiGammaY0493x6g.data() : nullptr,
                    phaseGasPressureApplySpecies0493x6g ? 1 : 0,
                    registeredGasPhase0493x7m ? 1 : 0,
                    grid.Nx, grid.Ny, periodicX, periodicY,
''',
    "kernel call phase gate",
)

readme = '''# 0493x7m — Q6-g-f monophase interface guard

## Problem

Historical single-phase run_ok cases register one liquid species and no gas
species, but still use `free_surface_masked` with x6c/x6f. Ordinary MPCD
density fluctuations can therefore push filtered alpha below 0.5 locally and
manufacture a pressure-release hole although the carrier remains fully
supported.

The 300x300 same-face IO qualification exposed exactly this: carrier cells
remained 90000 while pressure cells changed to 89999, with four active-active
alpha=0.5 crossings. Both the x7j resident CG and its host fallback then failed
on the same artificial masked operator.

## Fix

The species registry is authoritative for phase topology. If at least one
registered species has `phaseFamily=gas`, x6f is unchanged.

If no gas phase is registered, x6f remains enabled but prepares the monophase
limit:

    pressureMask = carrierMask
    faceCoeff = 1 on carrier-carrier faces
    faceCoeff = 0 across carrier truncation

The alpha field may still be reconstructed for diagnostics, but its 0.5
crossings are not pressure boundaries in this monophase limit.

Keeping x6f enabled preserves the x7j fully resident CG path.

The liquid-only free-surface x5a case remains unchanged because it deliberately
registers a second gas-labelled species even when that phase has no active
particles. Explicit liquid/gas cases likewise retain the existing x6f/x6g
operator.

No new user parameter, threshold, environment flag, particle pass, or equation
is introduced.
'''

SRC.write_text(text)
README.write_text(readme)
print("[0493x7m] patched src/cuda_q6_resident_0400.cu")
print("[0493x7m] wrote README_0493X7M_Q6_G_F_MONOPHASE_INTERFACE_GUARD.md")
