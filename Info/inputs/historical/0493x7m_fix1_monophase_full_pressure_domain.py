#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src" / "cuda_q6_resident_0400.cu"
README = ROOT / "README_0493X7M_Q6_G_F_MONOPHASE_INTERFACE_GUARD.md"

def replace_once(text: str, old: str, new: str, label: str) -> str:
    n = text.count(old)
    if n != 1:
        raise SystemExit(f"[0493x7m-fix1] ERROR {label}: expected exactly 1 match, got {n}")
    return text.replace(old, new, 1)

text = SRC.read_text()

text = replace_once(
    text,
    '''        const bool pressureC =
            carrierMask[c] != 0u && (!usePhaseInterface0493x7m || alphaC >= 0.5);
''',
    '''        const bool pressureC =
            !usePhaseInterface0493x7m ||
            (carrierMask[c] != 0u && alphaC >= 0.5);
''',
    "center monophase full pressure domain",
)

text = replace_once(
    text,
    '''            const bool pressureE =
                carrierMask[east] != 0u &&
                (!usePhaseInterface0493x7m || alphaE >= 0.5);
''',
    '''            const bool pressureE =
                !usePhaseInterface0493x7m ||
                (carrierMask[east] != 0u && alphaE >= 0.5);
''',
    "east monophase full pressure domain",
)

text = replace_once(
    text,
    '''            const bool pressureN =
                carrierMask[north] != 0u &&
                (!usePhaseInterface0493x7m || alphaN >= 0.5);
''',
    '''            const bool pressureN =
                !usePhaseInterface0493x7m ||
                (carrierMask[north] != 0u && alphaN >= 0.5);
''',
    "north monophase full pressure domain",
)

text = replace_once(
    text,
    '''        // 0493x7m: alpha=0.5 is a phase boundary only when the registry
        // actually contains a gas phase. In an explicitly monophase liquid
        // registry, density fluctuations must not create pressure-release holes.
''',
    '''        // 0493x7m-fix1: alpha=0.5 is a phase boundary only when the registry
        // actually contains a gas phase. In an explicitly monophase liquid
        // registry the pressure domain is the full computational grid:
        // particle-density fluctuations or transient empty carrier cells are
        // sampling defects, not physical pressure boundaries.
''',
    "comment",
)

readme = README.read_text()
readme = replace_once(
    readme,
    '''If no gas phase is registered, x6f remains enabled but prepares the monophase
limit:

    pressureMask = carrierMask
    faceCoeff = 1 on carrier-carrier faces
    faceCoeff = 0 across carrier truncation

The alpha field may still be reconstructed for diagnostics, but its 0.5
crossings are not pressure boundaries in this monophase limit.
''',
    '''If no gas phase is registered, x6f remains enabled but prepares the monophase
limit on the full computational grid:

    pressureMask = 1 for every computational cell
    faceCoeff = 1 on every internal computational face

The particle carrier remains a separate velocity/application mask. Therefore an
empty MPCD cell has zero local sampled velocity but remains a valid pressure
unknown. Its temporary loss of particles is a sampling defect, not a physical
free surface or a pressure boundary.

The alpha field may still be reconstructed for diagnostics, but neither its 0.5
crossings nor transient carrier holes are pressure boundaries in this monophase
limit.
''',
    "README monophase definition",
)

readme += '''

## fix1 — persistent monophase pressure domain

The initial x7m guard still used `pressureMask=carrierMask` in the monophase
limit. Bend-pipe startup showed why that remained insufficient: after 613
successful steps, two cells inside the filled Brinkman fictitious solid became
temporarily empty. The carrier therefore dropped from 16384 to 16382 cells and
created five zero-coefficient truncation faces. The remaining pressure component
was pure Neumann but its RHS sum was nonzero, so both mathematical compatibility
and CG convergence were lost.

fix1 makes the monophase pressure domain independent of instantaneous particle
occupancy. This is consistent with the fictitious-domain Darcy contract and with
single-phase incompressible projection generally. The existing RHS already
carries separate solve and velocity masks, so no particle velocity is invented
inside an empty cell. When the full grid is active the existing full-domain
null-space treatment subtracts the RHS mean.

Two-phase / liquid-vacuum cases with a registered gas phase are unchanged.
'''

SRC.write_text(text)
README.write_text(readme)
print("[0493x7m-fix1] patched monophase pressure domain to full computational grid")
print("[0493x7m-fix1] updated README_0493X7M_Q6_G_F_MONOPHASE_INTERFACE_GUARD.md")
