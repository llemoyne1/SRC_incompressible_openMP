
# 0493x14w — two-phase Couette / tangential gas-liquid transfer

No C++/CUDA modification is included.

## Source inspection result

The existing `wall` backend is sufficient.

For a y-normal `solid` wall, streaming reflects only the normal velocity.
Tangential wall motion is imposed by the already-existing thermal virtual
particle contribution to the SRC collision cell.  This is the same generic
solid-wall coupling used by the characterized Poiseuille path.

The runner deliberately uses

    G_bottom | L | G_top

instead of `L|G`, so both physical walls touch gas.  The global wall virtual
particle parameters can therefore be set consistently to gas values
`gamma=20, m=0.1, kBT=0.08` on both walls.  The liquid never touches a physical
wall, so wall calibration cannot be confused with the liquid/gas interface.

Bottom/top wall velocities are `-Uw/+Uw`.  The centered geometry gives an
antisymmetric Couette profile.

## Default geometry

    Lx = Ly = 0.5
    Nx = Ny = 128
    h = 1/256

    gas bottom: 32 cells
    liquid:     64 cells
    gas top:    32 cells

The 64-cell liquid slab is intentionally thicker than `2*Rc` for the x12a
local-thickness radius (`Rc/h ~= 25.3`), so the thin-sheet cooling law is not
artificially activated in the liquid core.

Default wall speed:

    Uw = 0.02

Default capillarity:

    sigma = 2560

For a perfectly planar interface kappa=0, so capillarity contributes no target
tangential traction; the strong value only suppresses accidental interface
corrugation while tangential transfer is isolated.

## What is measured

State dumps are analyzed offline.  No new runtime diagnostic is added.

The analyzer mirror-averages top and bottom halves:

    u_a(z) = [u_top(z) - u_bottom(z)] / 2

and fits separate straight lines in liquid and gas, excluding 4 cells around
the interface and 4 cells near the walls.

Primary result:

    Delta u_Gamma = u_G^Gamma - u_L^Gamma

Tangential velocity continuity requires this to approach zero.

It also reports

    a_L / a_G

which equals `mu_G/mu_L` if tangential stress is continuous, plus gas-wall
slip, R^2 values, normal velocity RMS, and convergence from the previous dump.

## Install

```bash
cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF
unzip -o /path/to/0493x14w_two_phase_couette_runner.zip

python3 -m py_compile scripts/analyze_0493x14w_two_phase_couette.py
bash -n scripts/run_ok_0493x14w_two_phase_couette.sh
```

x14v must already be applied; the runner checks its source marker.

## Optional visual smoke

```bash
STEPS=3000 \
DUMP_STATE_EVERY=1000 \
SUMMARY_EVERY=500 \
LIVE_VIS_ENABLE=1 \
LIVE_VIS_HOLD_ON_EXIT=1 \
bash scripts/run_ok_0493x14w_two_phase_couette.sh
```

This is only a geometry/qualitative smoke.  It is not the tangential
qualification.

## Quantitative run

```bash
STEPS=18000 \
DUMP_STATE_EVERY=3000 \
SUMMARY_EVERY=1000 \
LIVE_VIS_ENABLE=0 \
FILTERED_RECORDING_ENABLE=0 \
RECORD_ENABLE=false \
bash scripts/run_ok_0493x14w_two_phase_couette.sh
```

Return:

    runs/0493x14w_two_phase_couette/
    0493x14w_two_phase_couette_compact.tar.gz

If the last two dumps are not sufficiently converged, extend the same benchmark
rather than changing geometry or physics.
