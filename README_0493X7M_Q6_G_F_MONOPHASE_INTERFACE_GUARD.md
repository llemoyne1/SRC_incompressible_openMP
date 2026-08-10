# 0493x7m — Q6-g-f monophase interface guard

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

Keeping x6f enabled preserves the x7j fully resident CG path.

The liquid-only free-surface x5a case remains unchanged because it deliberately
registers a second gas-labelled species even when that phase has no active
particles. Explicit liquid/gas cases likewise retain the existing x6f/x6g
operator.

No new user parameter, threshold, environment flag, particle pass, or equation
is introduced.


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
